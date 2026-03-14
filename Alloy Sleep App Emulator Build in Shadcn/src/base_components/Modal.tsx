import Overlay from './Overlay.tsx'
import React, { CSSProperties, type ReactNode, useCallback, useEffect, useRef } from 'react'

interface ModalProps {
  children?: ReactNode
  onClose?: () => void
  id?: string
  unclosable?: boolean,
}

// Ensure all children are given styling that matches the rest of the app.

const Modal: React.FC<ModalProps> = ({
                                       children,
                                       onClose,
                                       id,
                                       unclosable = false
                                     }) => {
  const backgroundRef = useRef<HTMLDivElement>(null)
  const mouseDownTargetRef = useRef<HTMLElement | null>(null)


  const goBack = useCallback(() => {
    if (unclosable) {
      return
    }
    if (onClose) {
      onClose()
    }
  }, [onClose, unclosable])

  useEffect(() => {
    const keyListener = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        goBack()
      }
    }
    window.addEventListener('keydown', keyListener)

    return () => {
      window.removeEventListener('keydown', keyListener)
    }
  }, [goBack])

  const style: CSSProperties = {
    width: '100vw',
    height: '100vh',
    zIndex: 100,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center'
  }

  return (
    <Overlay darkenBg>
      <div
        style={style}
        id={id}
        ref={backgroundRef}
        onPointerDown={(e) => {
          mouseDownTargetRef.current = e.target as HTMLElement
        }}
        onPointerUp={(e) => {
          if (
            e.target === backgroundRef.current &&
            mouseDownTargetRef.current === backgroundRef.current
          ) {
            goBack()
          }
          mouseDownTargetRef.current = null
        }}
      >
        {children}
      </div>
    </Overlay>
  )
}

export default Modal
