import {
  autoUpdate,
  flip,
  FloatingPortal,
  offset,
  type Placement,
  shift,
  useDelayGroup,
  useDelayGroupContext,
  useDismiss,
  useFloating,
  useFocus,
  useHover,
  useInteractions,
  useMergeRefs,
  useRole,
  useTransitionStyles
} from '@floating-ui/react'
import * as React from 'react'
import { CSSProperties, useContext, useMemo, useState } from 'react'

interface TooltipOptions {
  initialOpen?: boolean
  placement?: Placement
  open?: boolean
  onOpenChange?: (open: boolean) => void
  disabled?: boolean
}

export function useTooltip({
                             initialOpen = false,
                             placement = 'top',
                             open: controlledOpen,
                             onOpenChange: setControlledOpen,
                             disabled
                           }: TooltipOptions = {}) {
  const [uncontrolledOpen, setUncontrolledOpen] = useState(initialOpen)

  const open = (!disabled && controlledOpen) ?? uncontrolledOpen
  const setOpen = setControlledOpen ?? setUncontrolledOpen
  const { delay } = useDelayGroupContext()

  const data = useFloating({
    placement,
    open,
    onOpenChange: setOpen,
    whileElementsMounted: autoUpdate,
    middleware: [
      offset(5),
      flip({
        fallbackAxisSideDirection: 'start'
      }),
      shift({ padding: 5 })
    ]
  })

  const context = data.context
  const hover = useHover(context, {
    move: false,
    /* eslint-disable */
    enabled: controlledOpen == null,
    delay: { open: delay as number, close: 0 }
  })
  const focus = useFocus(context, {
    /* eslint-disable */
    enabled: controlledOpen == null
  })
  const dismiss = useDismiss(context)
  const role = useRole(context, { role: 'tooltip' })

  const interactions = useInteractions([hover, focus, dismiss, role])

  return useMemo(
    () => ({
      open,
      setOpen,
      ...interactions,
      ...data
    }),
    [open, setOpen, interactions, data]
  )
}

type ContextType = ReturnType<typeof useTooltip> | null

const TooltipContext = React.createContext<ContextType>(null)

export const useTooltipContext = () => {
  const context = useContext(TooltipContext)

  /* eslint-disable */
  if (context == null) {
    throw new Error('Tooltip components must be wrapped in <Tooltip />')
  }

  return context
}

export function Tooltip({ children, ...options }: { children: React.ReactNode } & TooltipOptions) {
  // This can accept any props as options, e.g. `placement`,
  // or other positioning options.
  const tooltip = useTooltip(options)
  return <TooltipContext.Provider value={tooltip}>{children}</TooltipContext.Provider>
}

export const TooltipTrigger = React.forwardRef<
  HTMLElement,
  React.HTMLProps<HTMLElement> & { asChild?: boolean }
>(function TooltipTrigger({ children, asChild = false, ...props }, propRef) {
  const context = useTooltipContext()
  const childrenRef = (children as any).ref
  const ref = useMergeRefs([context.refs.setReference, propRef, childrenRef])

  // `asChild` allows the user to pass any element as the anchor
  if (asChild && React.isValidElement(children)) {
    return React.cloneElement(
      children,
      context.getReferenceProps({
        ref,
        ...props,
        ...children.props,
        'data-state': context.open ? 'open' : 'closed'
      })
    )
  }

  return (
    <div
      ref={ref}
      // The user can style the trigger based on the state
      data-state={context.open ? 'open' : 'closed'}
      {...context.getReferenceProps(props)}
      className={props.className}
      style={props.style}
    >
      {children}
    </div>
  )
})

export const TooltipContent = React.forwardRef<
  HTMLDivElement,
  Omit<React.HTMLProps<HTMLDivElement>, 'style'>
>(function TooltipContent(props, propRef) {
  const context = useTooltipContext()
  const { isInstantPhase, currentId } = useDelayGroupContext()
  const ref = useMergeRefs([context.refs.setFloating, propRef])

  useDelayGroup(context.context, { id: context.context.floatingId })

  const instantDuration = 0
  const duration = 200

  const { isMounted, styles } = useTransitionStyles(context.context, {
    duration: isInstantPhase
      ? {
        open: instantDuration,
        // `id` is this component's `id`
        // `currentId` is the current group's `id`
        close: currentId === context.context.floatingId ? duration : instantDuration
      }
      : { open: duration, close: instantDuration },
    initial: {
      opacity: 0
    }
  })

  const tooltipStyles: CSSProperties = {
    background: '#222',
    color: '#f0f0f0',
    padding: '4px 8px',
    borderRadius: '7px',
    boxSizing: 'border-box',
    width: 'max-content',
    maxWidth: 'calc(100vw - 10px)',
    zIndex: 2147483647
  }

  if (!isMounted) return null

  return (
    <FloatingPortal>
      <div
        ref={ref}
        style={{
          ...context.floatingStyles,
          ...tooltipStyles,
          ...styles
        }}
        {...context.getFloatingProps(props)}
        className={props.className}
      />
    </FloatingPortal>
  )
})
