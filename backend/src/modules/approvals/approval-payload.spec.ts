import { canonicalPayload, validateApprovalPayload } from './approval-payload';

describe('approval payloads', () => {
  it('matches a discount only when value and items are identical', () => {
    const approved = canonicalPayload('DISCOUNT', { type: 'PERCENT', value: 20, itemIds: ['b', 'a'] });
    expect(canonicalPayload('DISCOUNT', { type: 'PERCENT', value: 20, itemIds: ['a', 'b'] })).toBe(approved);
    expect(canonicalPayload('DISCOUNT', { type: 'PERCENT', value: 25, itemIds: ['a', 'b'] })).not.toBe(approved);
  });

  it('keeps whole-order and item voids apart', () => {
    expect(canonicalPayload('VOID', { itemIds: 'order' })).not.toBe(canonicalPayload('VOID', { itemIds: ['x'] }));
  });

  it('rejects a void with no items and a discount with no value', () => {
    expect(() => validateApprovalPayload('VOID', { itemIds: [] })).toThrow();
    expect(() => validateApprovalPayload('DISCOUNT', { type: 'PERCENT', value: 0 })).toThrow();
    expect(() => validateApprovalPayload('NO_SALE', {})).not.toThrow();
  });
});
