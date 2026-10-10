import { useMemo } from 'react';
import { LabelsManager } from '@/hooks/Mapper/utils/labelsManager';
import { getLabelDefinition, SystemLabelDefinition } from '@/hooks/Mapper/constants/labels';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';

interface UseLabelsInfoParams {
  labels: string | null;
  linkedSigPrefix: string | null;
  isShowLinkedSigId: boolean;
}

export type LabelInfo = SystemLabelDefinition;

/**
 * Both the label ids on a system and the definitions they point at are the map's, shared by
 * everybody on it. An id with no definition - one removed from the list, or carried in from
 * another map - is still rendered, with its raw id and a neutral colour.
 */
function sortedLabels(labelIds: string[], definitions: SystemLabelDefinition[]): LabelInfo[] {
  if (!labelIds) return [];

  const ids = labelIds.filter(id => id.trim() !== '');

  const known = definitions.filter(x => ids.includes(x.id));
  const unknown = ids.filter(id => !definitions.some(x => x.id === id)).map(id => getLabelDefinition([], id));

  return [...known, ...unknown];
}

export function useLabelsInfo({ labels, linkedSigPrefix, isShowLinkedSigId }: UseLabelsInfoParams) {
  const {
    userRemoteSettings: { systemLabels },
  } = useMapRootState();

  const labelsManager = useMemo(() => new LabelsManager(labels ?? ''), [labels]);
  const labelsInfo = useMemo(() => sortedLabels(labelsManager.list, systemLabels), [labelsManager, systemLabels]);
  const labelCustom = useMemo(() => {
    if (isShowLinkedSigId && linkedSigPrefix) {
      return labelsManager.customLabel ? `${linkedSigPrefix}・${labelsManager.customLabel}` : linkedSigPrefix;
    }
    return labelsManager.customLabel;
  }, [linkedSigPrefix, isShowLinkedSigId, labelsManager]);

  return { labelsInfo, labelCustom };
}
