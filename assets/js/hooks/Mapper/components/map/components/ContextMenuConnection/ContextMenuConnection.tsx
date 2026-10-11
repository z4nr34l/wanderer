import {
  BubbleState,
  ConnectionType,
  MassState,
  ShipSizeStatus,
  SolarSystemConnection,
  TimeStatus,
  UserPermission,
} from '@/hooks/Mapper/types';
import clsx from 'clsx';
import { PrimeIcons } from 'primereact/api';
import { ContextMenu } from 'primereact/contextmenu';
import { MenuItem } from 'primereact/menuitem';
import React, { RefObject, useMemo } from 'react';
import { Edge } from 'reactflow';
import { LifetimeActionsWrapper } from '@/hooks/Mapper/components/map/components/ContextMenuConnection/LifetimeActionsWrapper.tsx';
import { MassStatusActionsWrapper } from '@/hooks/Mapper/components/map/components/ContextMenuConnection/MassStatusActionsWrapper.tsx';
import { ShipSizeActionsWrapper } from '@/hooks/Mapper/components/map/components/ContextMenuConnection/ShipSizeActionsWrapper.tsx';
import classes from './ContextMenuConnection.module.scss';
import { getSystemStaticInfo } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic.ts';
import { isNullsecSpace } from '@/hooks/Mapper/components/map/helpers/isKnownSpace.ts';
import { useMapState } from '@/hooks/Mapper/components/map/MapProvider.tsx';
import { checkPermissions } from '@/hooks/Mapper/components/map/helpers';

export interface ContextMenuConnectionProps {
  contextMenuRef: RefObject<ContextMenu>;
  onDeleteConnection(): void;
  onChangeTimeState(lifetime: TimeStatus): void;
  onChangeMassState(state: MassState): void;
  onChangeShipSizeStatus(state: ShipSizeStatus): void;
  onChangeType(type: ConnectionType): void;
  onToggleMassSave(isLocked: boolean): void;
  onToggleDangerous(dangerous: boolean): void;
  onChangeBubbled(bubbled: BubbleState): void;
  onHide(): void;
  edge?: Edge<SolarSystemConnection>;
}

export const ContextMenuConnection: React.FC<ContextMenuConnectionProps> = ({
  contextMenuRef,
  onDeleteConnection,
  onChangeTimeState,
  onChangeMassState,
  onChangeShipSizeStatus,
  onChangeType,
  onToggleMassSave,
  onToggleDangerous,
  onChangeBubbled,
  onHide,
  edge,
}) => {
  const {
    data: { userPermissions },
  } = useMapState();

  const items: MenuItem[] = useMemo(() => {
    if (!edge) {
      return [];
    }

    // the server only takes these from someone allowed to make them, so a viewer is not offered
    // options that would do nothing when clicked
    const canEdit = checkPermissions(userPermissions, UserPermission.UPDATE_SYSTEM);
    const disconnect: MenuItem[] = checkPermissions(userPermissions, UserPermission.DELETE_CONNECTION)
      ? [{ label: 'Disconnect', icon: PrimeIcons.TRASH, command: onDeleteConnection }]
      : [];

    if (!canEdit) {
      return disconnect;
    }

    const sourceInfo = getSystemStaticInfo(edge.data?.source);
    const targetInfo = getSystemStaticInfo(edge.data?.target);

    const bothNullsec =
      sourceInfo && targetInfo && isNullsecSpace(sourceInfo.system_class) && isNullsecSpace(targetInfo.system_class);

    const isFrigateSize = edge.data?.ship_size_type === ShipSizeStatus.small;

    const isDangerous = edge.data?.dangerous === true;
    const bubbled = edge.data?.bubbled ?? BubbleState.none;

    const safetyItems: MenuItem[] = [
      {
        label: 'Dangerous',
        icon: clsx(PrimeIcons.EXCLAMATION_TRIANGLE, { 'text-red-400': isDangerous }),
        className: clsx({ [classes.ConnectionSave]: isDangerous }),
        command: () => onToggleDangerous(!isDangerous),
      },
      {
        label: 'Bubbled',
        icon: PrimeIcons.CIRCLE,
        className: clsx({ [classes.ConnectionSave]: bubbled !== BubbleState.none }),
        items: [
          { state: BubbleState.none, label: 'None' },
          { state: BubbleState.source, label: 'Source side' },
          { state: BubbleState.target, label: 'Target side' },
          { state: BubbleState.both, label: 'Both sides' },
        ].map(({ state, label }) => ({
          label,
          icon: state === bubbled ? PrimeIcons.CHECK : PrimeIcons.CIRCLE,
          command: () => onChangeBubbled(state),
        })),
      },
    ];

    if (edge.data?.type === ConnectionType.bridge) {
      return [
        {
          label: `Set as Wormhole`,
          icon: 'pi hero-arrow-uturn-left',
          command: () => onChangeType(ConnectionType.wormhole),
        },
        ...safetyItems,
        ...disconnect,
      ];
    }

    if (edge.data?.type === ConnectionType.gate) {
      return [...safetyItems, ...disconnect];
    }

    return [
      {
        className: clsx(classes.FastActions, '!h-[54px]'),
        template: () => {
          return <LifetimeActionsWrapper lifetime={edge.data?.time_status} onChangeLifetime={onChangeTimeState} />;
        },
      },
      ...(!isFrigateSize
        ? [
            {
              className: clsx(classes.FastActions, '!h-[54px]'),
              template: () => {
                return (
                  <MassStatusActionsWrapper
                    massStatus={edge.data?.mass_status}
                    onChangeMassStatus={onChangeMassState}
                  />
                );
              },
            },
          ]
        : []),
      {
        className: clsx(classes.FastActions, '!h-[64px]'),
        template: () => {
          return (
            <ShipSizeActionsWrapper shipSize={edge.data?.ship_size_type} onChangeShipSize={onChangeShipSizeStatus} />
          );
        },
      },
      {
        label: `Save mass`,
        className: clsx({
          [classes.ConnectionSave]: edge.data?.locked,
        }),
        icon: PrimeIcons.LOCK,
        command: () => onToggleMassSave(!edge.data?.locked),
      },
      ...safetyItems,
      ...(bothNullsec
        ? [
            {
              label: `Set as Bridge`,
              icon: 'pi hero-forward',
              command: () => onChangeType(ConnectionType.bridge),
            },
          ]
        : []),
      ...disconnect,
    ];
  }, [
    userPermissions,
    onToggleDangerous,
    onChangeBubbled,
    edge,
    onChangeTimeState,
    onDeleteConnection,
    onChangeType,
    onChangeShipSizeStatus,
    onToggleMassSave,
    onChangeMassState,
  ]);

  return (
    <>
      <ContextMenu model={items} ref={contextMenuRef} onHide={onHide} breakpoint="767px" className="!w-[250px]" />
    </>
  );
};
