/**
 * Legacy `role` claim (PLAN 1.5). Kept so older @Roles routes keep working until Phase 2:
 * admin persona -> ADMIN, kiosk persona -> KIOSK, everything else -> USER.
 */
export function legacyRoleFor(personaKey: string): 'ADMIN' | 'USER' | 'KIOSK' {
  if (personaKey === 'admin') return 'ADMIN';
  if (personaKey === 'kiosk') return 'KIOSK';
  return 'USER';
}
