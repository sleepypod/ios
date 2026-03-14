import { autoUpdate, flip, offset, type Placement, shift, useFloating } from '@floating-ui/react'
import Overlay from './Overlay.tsx'
import React, { useCallback, useEffect, useState } from 'react'
import { OutsidePointerdownHandler } from './OutsidePointerdownHandler.tsx'

export type DropdownAlignment =
  | 'left'
  | 'right'
  | 'outside-left'
  | 'outside-right'
  | 'above-left'
  | 'center'

interface DropdownProps<T = HTMLElement> {
  alignment: DropdownAlignment
  onClose?: () => void
  buttonRef?: React.RefObject<T>
  children?: React.ReactNode
  overlay?: boolean
  extraRoundedCorners?: boolean
  mousePosition?: { x: number; y: number }
  submenuShift?: boolean
  style?: any
  blurEnabled?: boolean
  offset?: { x: number; y: number }
  avoidCollision?: boolean
  ignoreOutsideClick?: (e: PointerEvent) => boolean
  positionTransform?: boolean
}

function mapAlignmentToPlacement(alignment: DropdownAlignment): Placement | undefined {
  switch (alignment) {
    case 'outside-left':
      return 'left-start'
    case 'outside-right':
      return 'right-start'
    case 'left':
      return 'bottom-start'
    case 'right':
      return 'bottom-end'
    case 'above-left':
      return 'top-start'
    default:
      break
  }
}

const Dropdown = ({
                    onClose,
                    buttonRef,
                    alignment,
                    children,
                    overlay = true,
                    extraRoundedCorners = false,
                    mousePosition,
                    submenuShift = false,
                    style,
                    blurEnabled = true,
                    offset: inputOffset = { y: 4, x: 0 },
                    avoidCollision = false,
                    ignoreOutsideClick,
                    positionTransform = false
                  }: DropdownProps) => {
  const { refs, floatingStyles, isPositioned } = useFloating({
    placement: mapAlignmentToPlacement(alignment),
    strategy: 'fixed',
    middleware: [
      offset({
        mainAxis: submenuShift ? 4 : inputOffset?.y,
        crossAxis: submenuShift ? -9 : inputOffset?.x
      }),
      shift({
        padding: 10,
        mainAxis: avoidCollision,
        crossAxis: !avoidCollision
      }),
      flip()
    ],
    whileElementsMounted: autoUpdate
  })

  useEffect(() => {
    if (buttonRef && 'current' in buttonRef) {
      refs.setReference(buttonRef.current)
    } else if (mousePosition) {
      refs.setPositionReference({
        getBoundingClientRect() {
          return {
            width: 0,
            height: 0,
            x: mousePosition.x,
            y: mousePosition.y,
            top: mousePosition.y,
            right: mousePosition.x,
            bottom: mousePosition.y,
            left: mousePosition.x
          }
        }
      })
    }
  }, [buttonRef, mousePosition, refs])

  const [prepareDropdownClose, setPrepareDropdownClose] = useState<boolean>(false)

  const delay = async (ms: number) => await new Promise((resolve) => setTimeout(resolve, ms))

  const handleClose = useCallback(async () => {
    if (onClose) {
      setPrepareDropdownClose(true)
      await delay(150)
      onClose()
      setPrepareDropdownClose(false)
    }
  }, [onClose])

  useEffect(() => {
    const handleKeydown = async (e: { key: string }) => {
      if (e.key === 'Escape') {
        await handleClose()
      }
    }

    document.addEventListener('keydown', handleKeydown)

    return () => {
      document.removeEventListener('keydown', handleKeydown)
    }
  }, [handleClose])

  const onClickOutside = useCallback(
    async (e: PointerEvent) => {
      if (ignoreOutsideClick?.(e)) {
        return
      }
      await handleClose()
    },
    [handleClose, ignoreOutsideClick]
  )

  const [hasBeenPositioned, setHasBeenPositioned] = useState(false)
  useEffect(() => {
    if (isPositioned) {
      setHasBeenPositioned(true)
    }
  }, [isPositioned])

  const dropdownStyle: React.CSSProperties = {
    pointerEvents: 'auto',
    position: 'absolute',
    margin: '4px 0',
    transformOrigin: 'top right',
    overflow: 'hidden',
    opacity: !isPositioned ? 0 : 1,
    ...(isPositioned && {
      animation: 'dropdownFadeIn 150ms forwards'
    }),
    ...(prepareDropdownClose && {
      animation: 'dropdownFadeOut 150ms forwards'
    }),
    ...(hasBeenPositioned && positionTransform && {
      transition: 'transform 150ms ease-in-out'
    }),
    ...style,
    ...(isPositioned ? floatingStyles : {})
  }

  return (
    <>
      <style>
        {`
          @keyframes dropdownFadeIn {
            from {
              opacity: 0;
            }
            to {
              opacity: 1;
            }
          }
          @keyframes dropdownFadeOut {
            from {
              opacity: 1;
            }
            to {
              opacity: 0;
            }
          }
        `}
      </style>
      <Overlay pointerEvents={overlay ? undefined : 'none'}>
        <OutsidePointerdownHandler onClickOutside={onClickOutside}>
          <div
            ref={refs.setFloating}
            style={dropdownStyle}
          >
            {children}
          </div>
        </OutsidePointerdownHandler>
      </Overlay>
    </>
  )
}

export default Dropdown
