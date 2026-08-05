import { describe, it, expect } from 'vitest';
import { isValidBusinessData } from '../utils';

describe('isValidBusinessData', () => {
  it('accepts an object with waba_id but no business_id (coexistence payload)', () => {
    expect(isValidBusinessData({ waba_id: 'waba-1' })).toBe(true);
  });

  it('accepts an object with both waba_id and business_id', () => {
    expect(
      isValidBusinessData({ waba_id: 'waba-1', business_id: 'biz-1' })
    ).toBe(true);
  });

  it('rejects an object without waba_id', () => {
    expect(isValidBusinessData({ business_id: 'biz-1' })).toBe(false);
  });

  it('rejects an empty object', () => {
    expect(isValidBusinessData({})).toBe(false);
  });

  it('rejects null', () => {
    expect(isValidBusinessData(null)).toBe(false);
  });

  it('rejects undefined', () => {
    expect(isValidBusinessData(undefined)).toBe(false);
  });

  it('rejects non-object values', () => {
    expect(isValidBusinessData('waba-1')).toBe(false);
    expect(isValidBusinessData(42)).toBe(false);
    expect(isValidBusinessData(true)).toBe(false);
  });
});
