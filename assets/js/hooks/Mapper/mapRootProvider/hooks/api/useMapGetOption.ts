import { useMemo } from 'react';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { MapOptions } from '@/hooks/Mapper/types';

export const useMapGetOption = (option: keyof MapOptions) => {
  const {
    data: { options },
  } = useMapRootState();

  return useMemo(() => options[option], [option, options]);
};
