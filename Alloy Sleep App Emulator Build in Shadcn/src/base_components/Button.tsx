import { Tooltip, TooltipContent, TooltipTrigger } from './Tooltip'
import React, { type CSSProperties, forwardRef, useCallback, useEffect, useRef, useState } from 'react'

interface ButtonProps {
  id?: string
  text?: string
  children?: React.ReactNode
  type?: 'button' | 'submit' | 'reset'
  autoFocus?: boolean
  dataTestId?: string
  className?: string
  onClick?: React.MouseEventHandler<HTMLButtonElement>
  onPointerDown?: React.MouseEventHandler<HTMLButtonElement>
  icon?: string
  leftIcon?: React.ReactNode
  rightIcon?: React.ReactNode
  active?: boolean
  disabled?: boolean
  tooltip?: string | React.ReactNode
  minWidth?: number
  style?: CSSProperties
  onHold?: { holdDuration: number; onHold: () => void }
  noScale?: boolean
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      id,
      text,
      leftIcon,
      rightIcon,
      children,
      onClick,
      onPointerDown: onMouseDown,
      type = 'button',
      autoFocus,
      dataTestId,
      disabled,
      tooltip,
      minWidth,
      onHold,
      style = {}
    },
    ref
  ) => {

    const [buttonPressed, setButtonPressed] = useState(false)
    const mouseHoldTimeoutRef = useRef<any>(null)
    const mouseHoldIntervalRef = useRef<any>(null)

    useEffect(() => {
      if (buttonPressed) {
        const onMouseUp = () => {
          setButtonPressed(false)
          clearTimeout(mouseHoldTimeoutRef.current)
          clearInterval(mouseHoldIntervalRef.current)
        }
        document.addEventListener('mouseup', onMouseUp)
        return () => {
          document.removeEventListener('mouseup', onMouseUp)
        }
      }
    }, [buttonPressed])

    const onPointerDown = useCallback(
      (e: React.PointerEvent<HTMLButtonElement>) => {
        setButtonPressed(true)
        if (onMouseDown) {
          onMouseDown(e)
        }
        if (onHold) {
          mouseHoldTimeoutRef.current = setTimeout(() => {
            mouseHoldIntervalRef.current = setInterval(onHold.onHold, 100)
          }, onHold.holdDuration)
        }
      },
      [onHold, onMouseDown]
    )

    const ButtonContent = (
      <button
        id={id}
        autoFocus={autoFocus}
        onClick={onClick}
        onPointerDown={onPointerDown}
        type={type}
        ref={ref}
        disabled={disabled}
        data-testid={dataTestId}
        style={{ minWidth: `${minWidth}px`, ...style }}
      >
        {leftIcon && (
          <div style={{
            display: 'flex',
            flexShrink: 0,
            maxWidth: '100%'
          }}>
            {leftIcon}
          </div>
        )}
        {text && (
          <span style={{
            whiteSpace: 'nowrap',
            textOverflow: 'ellipsis'
          }}>
            {text}
          </span>
        )}
        {children}
        {rightIcon}
      </button>
    )

    if (tooltip) {
      return (
        <Tooltip>
          <TooltipTrigger>
            {ButtonContent}
            <TooltipContent>{tooltip}</TooltipContent>
          </TooltipTrigger>
        </Tooltip>
      )
    } else {
      return ButtonContent
    }
  }
)

export default Button
