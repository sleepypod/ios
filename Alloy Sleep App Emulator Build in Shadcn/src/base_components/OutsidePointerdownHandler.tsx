import React, { CSSProperties, type ReactNode, useCallback, useEffect, useRef } from 'react'

export const OutsidePointerdownHandler = ({
                                            style,
                                            onClickOutside,
                                            children
                                          }: {
  style?: CSSProperties
  onClickOutside: (e: PointerEvent) => void
  children: ReactNode | ReactNode[]
}) => {
  const callbackRef = useRef<(e: PointerEvent) => void>()
  const insideClick = useRef(false)

  useEffect(() => {
    callbackRef.current = onClickOutside
  }, [onClickOutside])

  const handleInsidePointerDown = useCallback(() => {
    insideClick.current = true
  }, [insideClick])

  useEffect(() => {
    const handleOutsidePointerDown = (event: Event) => {
      const pointerEvent = event as PointerEvent
      // Ignore right-clicks (button === 2) as they're for context menus
      if (pointerEvent.button === 2) {
        insideClick.current = false
        return
      }

      // Check if the click was outside the React component
      if (!insideClick.current && callbackRef.current) {
        callbackRef.current(pointerEvent)
      }
      insideClick.current = false
    }

    document.addEventListener('pointerdown', handleOutsidePointerDown)

    return () => {
      document.removeEventListener('pointerdown', handleOutsidePointerDown)
    }
  }, [])

  return (
    <div style={style} onPointerDown={handleInsidePointerDown}>
      {children}
    </div>
  )
}
