import CheckIcon from '../base_icons/check.svg?react'
import React, { useCallback } from 'react'
import IndeterminateIcon from '../base_icons/indeterminate.svg?react'

type CheckboxStyle = {
  checkedBackgroundColor?: string,
  uncheckedBackgroundColor?: string,
  borderColor?: string
}

interface CommonCheckboxProps {
  onCheckChange?: (value: boolean, event: React.MouseEvent<HTMLDivElement>) => void
  context?: 'Picker'
  type?: 'standard' | 'indeterminate'
  dataTestId?: string,
  checkboxStyle?: CheckboxStyle
}

interface StandardCheckboxProps extends CommonCheckboxProps {
  checked: boolean
}

interface IntermediateCheckboxProps extends CommonCheckboxProps {
  checked: boolean | 'indeterminate'
  type: 'indeterminate'
}

type CheckboxProps = StandardCheckboxProps | IntermediateCheckboxProps

const Checkbox: React.FC<CheckboxProps> = ({
                                             checked,
                                             onCheckChange,
                                             context,
                                             checkboxStyle = {}


                                           }) => {
  const onClick = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      if (onCheckChange) {
        onCheckChange(!checked, event)
      }
    },
    [checked, onCheckChange]
  )

  const defaultStyle: Required<CheckboxStyle> = {
    checkedBackgroundColor: '#3269ff',
    uncheckedBackgroundColor: '#c2c2c2',
    borderColor: '#000000'
  }

  const checkboxFinalStyle = { ...defaultStyle, ...checkboxStyle }
  const getCheckboxStyle = (): React.CSSProperties => ({
    background: checked ? checkboxFinalStyle.checkedBackgroundColor : checkboxFinalStyle.uncheckedBackgroundColor,
    width: '15px',
    height: '15px',
    borderRadius: '7px',
    display: 'flex',
    flexShrink: 0,
    alignItems: 'center',
    justifyContent: 'center',
    border: `1.5px solid ${checkboxFinalStyle.borderColor}`,
    transition: 'background 100ms ease, transform 100ms ease, outline-color 100ms ease',
    position: 'relative',
    cursor: onCheckChange ? 'pointer' : 'default'
  })

  const getIconStyle = (): React.CSSProperties => ({
    width: '10px',
    height: '10px'
  })

  const getPickerContextStyle = (): React.CSSProperties => ({
    content: '',
    position: 'absolute',
    inset: '-10px'
  })

  return (
    <div
      onClick={(ev) => {
        if ((ev.target as HTMLElement).tagName === 'INPUT') ev.stopPropagation()
      }}
    >
      <div
        style={getCheckboxStyle()}
        onClick={onClick}
        onMouseDown={(e) => {
          if (onCheckChange) {
            e.currentTarget.style.transform = 'scale(0.95)'
          }
        }}
        onMouseUp={(e) => {
          if (onCheckChange) {
            e.currentTarget.style.transform = 'scale(1)'
          }
        }}
        onMouseLeave={(e) => {
          if (onCheckChange) {
            e.currentTarget.style.transform = 'scale(1)'
          }
        }}
      >
        {checked === true && (
          <CheckIcon
            style={{
              ...getIconStyle(),
              stroke: 'white',
              strokeWidth: '4px'
            }}
          />
        )}
        {checked === 'indeterminate' && (
          <IndeterminateIcon
            style={{
              ...getIconStyle(),
              stroke: 'white',
              strokeWidth: '4px'
            }}
          />
        )}
        {context === 'Picker' && <div style={getPickerContextStyle()} onClick={onClick} />}
      </div>
    </div>
  )
}

export default Checkbox
