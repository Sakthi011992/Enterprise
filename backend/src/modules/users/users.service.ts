import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { AppFeature } from '@prisma/client';
import { PrismaService } from '../../prisma/prisma.service';
import { PaginationDto, buildMeta } from '../../common/dto/pagination.dto';
import { CreateUserDto, UpdateUserDto } from './dto/user.dto';
import { UsersRepository } from './users.repository';

@Injectable()
export class UsersService {
  constructor(
    private repo: UsersRepository,
    private prisma: PrismaService,
  ) {}

  private async roleIdByName(name: string) {
    const role = await this.prisma.role.findUnique({ where: { name } });
    if (!role) throw new BadRequestException(`Unknown role: ${name}`);
    return role.id;
  }

  async findAll(q: PaginationDto) {
    const where = {
      deletedAt: null as null,
      ...(q.search
        ? { OR: [{ username: { contains: q.search, mode: 'insensitive' as const } }] }
        : {}),
    };
    const [data, total] = await this.prisma.$transaction([
      this.prisma.user.findMany({
        where,
        select: {
          id: true, username: true, isActive: true, createdAt: true, updatedAt: true,
          role: { select: { name: true } },
          featureGrants: { select: { feature: true } },
        },
        skip: q.skip,
        take: q.limit,
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.user.count({ where }),
    ]);
    return { data, meta: buildMeta(total, q.page, q.limit) };
  }

  async findOne(id: string) {
    const user = await this.repo.findById(id);
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async create(dto: CreateUserDto) {
    const roleId = await this.roleIdByName(dto.roleName ?? 'USER');
    const passwordHash = await bcrypt.hash(dto.password, 10);
    return this.repo.create({ username: dto.username, passwordHash, roleId });
  }

  async update(id: string, dto: UpdateUserDto) {
    await this.findOne(id);
    const data: Record<string, any> = {};
    if (dto.isActive !== undefined) data.isActive = dto.isActive;
    if (dto.roleName) data.role = { connect: { id: await this.roleIdByName(dto.roleName) } };
    if (dto.password) data.passwordHash = await bcrypt.hash(dto.password, 10);
    return this.prisma.user.update({
      where: { id },
      data,
      select: {
        id: true, username: true, isActive: true, createdAt: true, updatedAt: true,
        role: { select: { name: true } },
        featureGrants: { select: { feature: true } },
      },
    });
  }

  async resetPassword(id: string, newPassword: string) {
    await this.findOne(id);
    const passwordHash = await bcrypt.hash(newPassword, 10);
    await this.repo.updatePassword(id, passwordHash);
    return { success: true };
  }

  async remove(id: string) {
    await this.findOne(id);
    await this.repo.softDelete(id);
    return { success: true };
  }

  async getFeatures(id: string): Promise<AppFeature[]> {
    await this.findOne(id);
    const grants = await this.repo.getFeatures(id);
    return grants.map((g) => g.feature);
  }

  async setFeatures(id: string, features: AppFeature[]): Promise<AppFeature[]> {
    await this.findOne(id);
    await this.repo.setFeatures(id, features);
    return features;
  }
}
