import SearchIcon from '../base_icons/search.svg?react'
import React, {
  type ChangeEvent,
  CSSProperties,
  type FocusEvent,
  forwardRef,
  type InputHTMLAttributes,
  useCallback,
  useEffect,
  useRef,
  useState
} from 'react'
import XIcon from '../base_icons/x-close.svg?react'
import Button from './Button'

type InputProps = {
  placeholder?: string
  value?: string
  autoFocus?: boolean
  className?: string
  style?: CSSProperties
  appearance?: 'picker'
  onFocus?: (e: FocusEvent<HTMLInputElement>) => void
  onBlur?: (e: ChangeEvent<HTMLInputElement>) => void
  onKeyDown?: (e: React.KeyboardEvent<HTMLInputElement>) => void
  dataTestId?: string
  onChange?: (e: ChangeEvent<HTMLInputElement> | { target: any; type?: any }) => void
  onClose?: () => void
  showClose?: boolean
  id?: string
  name?: string
  type?: 'text' | 'password' | 'number' | 'email' | 'tel' | 'url'
} & InputHTMLAttributes<HTMLInputElement>
const Input = forwardRef<HTMLInputElement, InputProps>(
  (
    {
      placeholder,
      value,
      autoFocus,
      onChange,
      className,
      appearance,
      style,
      dataTestId,
      onClose,
      showClose,
      id,
      type,
      onKeyDown,
      ...rest
    },
    ref
  ) => {
    const iconRef = useRef(null)
    const [isShaking, setIsShaking] = useState(false)
    const [crossVisible, setCrossVisible] = useState(showClose || false)
    const [crossAnimation, setCrossAnimation] = useState('')

    useEffect(() => {
      if (showClose && !crossVisible) {
        setCrossVisible(true)
        setCrossAnimation('fadeIn')
      } else if (!showClose && crossVisible) {
        setCrossAnimation('fadeOut')
        setTimeout(() => setCrossVisible(false), 300)
      }
    }, [showClose, crossVisible])

    const handleChange = useCallback(
      (e: ChangeEvent<HTMLInputElement>) => {
        if (type === 'tel') {
          const inputValue = e.target.value
          e.target.value = inputValue.replace(/[^\d\s+\-()]/g, '')
        }
        onChange && onChange(e)
      },
      [onChange, type]
    )

    const handleKeyDown = useCallback(
      (e: React.KeyboardEvent<HTMLInputElement>) => {
        if (e.key === 'Escape') {
          /* @ts-expect-error blur */
          ref?.current?.blur()
        }
        onKeyDown?.(e)
      },
      [onKeyDown, ref]
    )

    const getInputContainerStyle = (): CSSProperties => ({
      width: '100%',
      position: 'relative'
    })

    const getSearchIconStyle = (): CSSProperties => ({
      position: 'absolute',
      pointerEvents: 'none',
      left: '11px',
      width: '15px',
      height: '15px',
      top: '50%',
      transform: 'translateY(-50%)'
    })

    const getInputStyle = (): CSSProperties => {
      const baseStyle: CSSProperties = {
        width: '100%',
        ...style
      }

      if (appearance === 'picker') {
        return {
          ...baseStyle,
          borderRadius: '8px 8px 0 0',
          flexGrow: 1,
          boxSizing: 'border-box',
          padding: '10px',
          transition: 'border 100ms ease-in-out',
          height: '40px'
        }
      }


      return {
        ...baseStyle,
        ...(onClose && { paddingRight: '32px' }),
        ...(type === 'number' && { width: 'fit-content', paddingRight: '0' })
      }
    }

    const getCloseButtonStyle = (): CSSProperties => ({
      position: 'absolute',
      top: '7px',
      right: '11px',
      borderRadius: '50px',
      opacity: crossAnimation === 'fadeIn' ? 1 : crossAnimation === 'fadeOut' ? 0 : crossVisible ? 1 : 0,
      transition: 'opacity 0.3s ease'
    })

    return (
      <>
        <style>
          {`
            @keyframes shake {
              0% { transform: translateX(0); filter: blur(0); }
              5% { transform: translateX(-5px); }
              15% { transform: translateX(5px); }
              25% { transform: translateX(-5px); filter: blur(1px); }
              35% { transform: translateX(5px); }
              45% { transform: translateX(-5px); }
              55% { transform: translateX(5px); }
              65% { transform: translateX(-5px); }
              75% { transform: translateX(4px); filter: blur(1px); }
              85% { transform: translateX(-4px); }
              100% { transform: translateX(0); filter: blur(0); }
            }
          `}
        </style>
        <div style={getInputContainerStyle()}>
          {(appearance === 'search' || appearance === 'sidenavGlobalSearch') && (
            <SearchIcon style={getSearchIconStyle()} />
          )}
          <input
            value={value}
            style={{
              ...getInputStyle(),
              ...(isShaking && { animation: 'shake 300ms ease-out' })
            }}
            ref={ref}
            data-testid={dataTestId}
            className={className}
            onChange={handleChange}
            onKeyDown={handleKeyDown}
            onFocus={rest.onFocus}
            onBlur={rest.onBlur}
            type={type || 'text'}
            autoFocus={autoFocus}
            placeholder={placeholder}
            {...rest}
          />
          {crossVisible && (
            <Button
              leftIcon={<XIcon />}
              onClick={onClose}
              ref={iconRef}
              style={getCloseButtonStyle()}
            />
          )}
        </div>
      </>
    )
  }
)

export default Input
