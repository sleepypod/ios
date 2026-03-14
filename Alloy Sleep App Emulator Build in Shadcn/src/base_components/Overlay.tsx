import React, { type ReactNode } from 'react'
import { createPortal } from 'react-dom'

interface OverlayProps {
  customCursor?: string
  darkenBg?: true
  pointerEvents?: 'none'
  children?: ReactNode
}

const Overlay = ({ customCursor, darkenBg, pointerEvents, children }: OverlayProps) => {
  const overlayStyle: React.CSSProperties = {
    position: 'fixed',
    zIndex: 9999,
    top: 0,
    left: 0,
    width: '100vw',
    height: '100vh',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    transition: 'background 500ms ease-in-out',
    background: 'lch(0% 0 0 / 0)',
    cursor: customCursor,
    pointerEvents: pointerEvents === 'none' ? 'none' : 'auto',
    ...(darkenBg && {
      animation: 'overlayFadeIn 200ms forwards'
    })
  }

  return (
    <>
      <style>
        {`
          @keyframes overlayFadeIn {
            from {
              background: lch(0% 0 0 / 0);
            }
            to {
              background: rgba(0, 0, 0, 0.2);
            }
          }
        `}
      </style>
      {createPortal(
        <div
          onClick={(e) => {
            e.stopPropagation()
          }}
          style={overlayStyle}
        >
          {children}
        </div>,
        document.body
      )}
    </>
  )
}

export default Overlay
