-- Managers approve discount requests (manager PIN on the POS). APPROVE is above LIMITED, so the
-- manager's own discounts are no longer capped at 30%. Only rows still at the shipped default
-- (LIMITED 30) change, so a matrix an admin has edited is left alone.
UPDATE "persona_permissions" pp
SET "level" = 'APPROVE', "limitValue" = NULL
FROM "personas" p
WHERE pp."personaId" = p."id"
  AND p."key" = 'manager'
  AND pp."permissionKey" = 'sales.discount.give'
  AND pp."level" = 'LIMITED'
  AND pp."limitValue" = 30;
