import { Injectable } from '@nestjs/common';
import { Prisma, Product, ProductVariant, Recipe, RecipeLine, TaxClass } from '@prisma/client';
import { AuthUser } from '../../common/decorators/current-user.decorator';
import { apiError } from '../../common/filters/api-error';
import { PermissionsService } from '../personas/permissions.service';
import { recipeQty } from '../stock-core/stock-math';
import { decimalInput } from './decimal-input';
import { PutRecipesDto } from './dto/recipes.dto';
import { InventoryRepository } from './inventory.repository';
import { HALF_UP, ZERO, cost6, money2 } from './inventory-views';

type RecipeWithLines = Recipe & { lines: RecipeLine[] };

/** Product recipes and their costing (PLAN.md 1.7 recipes, 1.4). Reads need stock.count VIEW and menu.edit VIEW. */
@Injectable()
export class RecipesService {
  constructor(
    private repo: InventoryRepository,
    private permissions: PermissionsService,
  ) {}

  async get(productId: string, auth: AuthUser) {
    if (!this.permissions.check(auth, 'menu.edit', 'VIEW')) {
      throw apiError(403, 'PERMISSION_DENIED', 'You do not have permission to do this', {
        permission: 'menu.edit',
        required: 'VIEW',
      });
    }
    return this.views(productId);
  }

  async replace(productId: string, dto: PutRecipesDto, auth: AuthUser) {
    const product = await this.repo.findProduct(productId);
    if (!product) throw apiError(404, 'PRODUCT_NOT_FOUND', 'Product not found');

    const variants = await this.repo.productVariants(productId);
    const variantIds = new Set(variants.map((v) => v.id));
    const seen = new Set<string>();
    for (const r of dto.recipes) {
      const key = r.variantId ?? 'ALL';
      if (seen.has(key)) {
        throw apiError(400, 'RECIPE_DUPLICATE_VARIANT', 'Only one recipe per variant', { variantId: r.variantId ?? null });
      }
      seen.add(key);
      if (r.variantId && !variantIds.has(r.variantId)) {
        throw apiError(400, 'INVALID_REFERENCE', 'Variant does not belong to this product', { variantId: r.variantId });
      }
    }

    const parsed = dto.recipes.map((r) => ({
      variantId: r.variantId ?? null,
      note: r.note ?? null,
      lines: r.lines.map((l, index) => ({
        stockItemId: l.stockItemId,
        qty: decimalInput(l.qty, 'qty', { dp: 3, min: 0.001 }) as Prisma.Decimal,
        wastagePercent: this.wastage(l.wastagePercent),
        sortOrder: index,
      })),
    }));

    const itemIds = [...new Set(parsed.flatMap((r) => r.lines.map((l) => l.stockItemId)))];
    const items = await this.repo.findItemsByIds(itemIds);
    if (items.length !== itemIds.length) {
      throw apiError(400, 'INVALID_REFERENCE', 'A stock item was not found', { stockItemIds: itemIds });
    }

    await this.repo.transaction(async (tx) => {
      await this.repo.deleteRecipesForProduct(tx, productId);
      for (const r of parsed) {
        await this.repo.createRecipe(tx, {
          tenantId: auth.tenantId,
          productId,
          variantId: r.variantId,
          note: r.note,
          lines: { create: r.lines },
        });
      }
    });
    return this.views(productId);
  }

  private wastage(value: unknown): Prisma.Decimal {
    const parsed = decimalInput(value, 'wastagePercent', { dp: 2, min: 0, optional: true });
    if (parsed === null) return ZERO;
    if (parsed.gt(100)) {
      throw apiError(400, 'VALIDATION_FAILED', 'wastagePercent must be 100 or less', { field: 'wastagePercent' });
    }
    return parsed;
  }

  /** One view per variant that has a recipe, plus the all-variants recipe (variantId null), which is always present. */
  private async views(productId: string) {
    const product = await this.repo.findProduct(productId);
    if (!product) throw apiError(404, 'PRODUCT_NOT_FOUND', 'Product not found');
    const variants = await this.repo.productVariants(productId);
    const recipes = (await this.repo.recipesForProduct(productId)) as RecipeWithLines[];
    const itemIds = [...new Set(recipes.flatMap((r) => r.lines.map((l) => l.stockItemId)))];
    const items = await this.repo.findItemsByIds(itemIds);
    const itemById = new Map(items.map((i) => [i.id, i]));
    const taxClass = product.taxClassId ? (await this.repo.taxClassesByIds([product.taxClassId]))[0] ?? null : null;

    const recipeFor = (variantId: string | null) => recipes.find((r) => r.variantId === variantId) ?? null;
    const out = [this.view(product, null, null, recipeFor(null), itemById, taxClass)];
    for (const v of variants) {
      const recipe = recipeFor(v.id);
      if (recipe) out.push(this.view(product, v, v.id, recipe, itemById, taxClass));
    }
    return out;
  }

  private view(
    product: Product,
    variant: ProductVariant | null,
    variantId: string | null,
    recipe: RecipeWithLines | null,
    itemById: Map<string, { name: string; baseUnit: string; avgCost: Prisma.Decimal }>,
    taxClass: TaxClass | null,
  ) {
    const price = variant ? variant.price : product.price;
    // Prices are exclusive of tax unless the tax class is inclusive (PLAN.md 1.7 pour cost is "price excl. tax").
    const priceExcl =
      taxClass && taxClass.inclusive && taxClass.rate.gt(0)
        ? price.div(new Prisma.Decimal(1).plus(taxClass.rate.div(100)))
        : price;

    const lines = (recipe?.lines ?? []).map((l) => {
      const item = itemById.get(l.stockItemId);
      const avgCost = item?.avgCost ?? ZERO;
      const cost = recipeQty(l.qty, l.wastagePercent, 1).mul(avgCost).toDecimalPlaces(2, HALF_UP);
      return {
        stockItemId: l.stockItemId,
        name: item?.name ?? null,
        baseUnit: item?.baseUnit ?? null,
        qty: l.qty.toDecimalPlaces(3, HALF_UP).toFixed(3),
        wastagePercent: l.wastagePercent.toDecimalPlaces(2, HALF_UP).toFixed(2),
        unitCost: cost6(avgCost),
        cost: money2(cost),
        costValue: cost,
      };
    });
    const costPerServing = lines.reduce((acc, l) => acc.plus(l.costValue), ZERO);
    const hasPrice = priceExcl.gt(0);
    return {
      variantId,
      variantName: variant ? variant.name : null,
      note: recipe?.note ?? null,
      lines: lines.map(({ costValue: _costValue, ...rest }) => rest),
      costPerServing: money2(costPerServing),
      sellingPrice: money2(price),
      pourCostPercent: hasPrice ? costPerServing.div(priceExcl).mul(100).toDecimalPlaces(1, HALF_UP).toFixed(1) : null,
      marginPercent: hasPrice
        ? priceExcl.minus(costPerServing).div(priceExcl).mul(100).toDecimalPlaces(1, HALF_UP).toFixed(1)
        : null,
    };
  }
}
