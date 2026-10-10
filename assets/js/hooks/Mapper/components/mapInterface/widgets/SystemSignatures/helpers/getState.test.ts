import { getState } from './getState';
import { UNKNOWN_SIGNATURE_NAME } from '@/hooks/Mapper/helpers';
import { SignatureGroup, SystemSignature } from '@/hooks/Mapper/types';

const asSignature = (fields: object) => fields as unknown as SystemSignature;

describe('getState', () => {
  const mockSignaturesMatch: string[] = []; // This parameter is not used in the function

  it('should return 0 if group is undefined', () => {
    const newSig = asSignature({ id: '1', name: 'Test Sig', group: undefined });
    expect(getState(mockSignaturesMatch, newSig)).toBe(0);
  });

  it('should return 0 if group is CosmicSignature', () => {
    const newSig = asSignature({ id: '1', name: 'Test Sig', group: SignatureGroup.CosmicSignature });
    expect(getState(mockSignaturesMatch, newSig)).toBe(0);
  });

  it('should return 1 if group is not CosmicSignature and name is undefined', () => {
    const newSig = asSignature({ id: '1', name: undefined, group: SignatureGroup.Wormhole });
    expect(getState(mockSignaturesMatch, newSig)).toBe(1);
  });

  it('should return 1 if group is not CosmicSignature and name is empty', () => {
    const newSig = asSignature({ id: '1', name: '', group: SignatureGroup.Wormhole });
    expect(getState(mockSignaturesMatch, newSig)).toBe(1);
  });

  it('should return 1 if group is not CosmicSignature and name is UNKNOWN_SIGNATURE_NAME', () => {
    const newSig = asSignature({ id: '1', name: UNKNOWN_SIGNATURE_NAME, group: SignatureGroup.Wormhole });
    expect(getState(mockSignaturesMatch, newSig)).toBe(1);
  });

  it('should return 2 if group is not CosmicSignature and name is a non-empty string', () => {
    const newSig = asSignature({ id: '1', name: 'Custom Name', group: SignatureGroup.Wormhole });
    expect(getState(mockSignaturesMatch, newSig)).toBe(2);
  });

  // According to the current implementation, state = -1 is unreachable
  // because the conditions for 0, 1, and 2 cover all possibilities for the given inputs.
  // If the logic of getState were to change to make -1 possible, a test case should be added here.
  // For now, we can test a scenario that should lead to one of the valid states,
  // for example, if group is something other than CosmicSignature and name is valid.
  it('should handle other valid signature groups correctly, leading to state 2 with a valid name', () => {
    const newSig = asSignature({ id: '1', name: 'Combat Site', group: SignatureGroup.CombatSite });
    expect(getState(mockSignaturesMatch, newSig)).toBe(2);
  });

  it('should handle other valid signature groups correctly, leading to state 1 with an empty name', () => {
    const newSig = asSignature({ id: '1', name: '', group: SignatureGroup.DataSite });
    expect(getState(mockSignaturesMatch, newSig)).toBe(1);
  });
});
