import React, { useEffect, useState } from 'react'

interface MouseSafeAreaProps {
  parentRef: React.RefObject<HTMLElement>
}

interface Positions {
  /* Sub-menu x */
  x: number
  /* Sub-menu y */
  y: number
  /* Sub-menu height */
  h: number
  /* Sub-menu width */
  w: number
  /* Mouse x */
  mouseX: number
  /* Mouse y */
  mouseY: number
}

const getLeft = ({ x, mouseX }: Positions) =>
  mouseX > x ? undefined : x - Math.max(x - mouseX, 10) + 'px'
const getRight = ({ x, w, mouseX }: Positions) =>
  mouseX > x ? x - Math.max(mouseX - (x + w), 10) + 'px' : undefined
const getWidth = ({ x, w, mouseX }: Positions) =>
  mouseX > x ? Math.max(mouseX - (x + w), 10) + 'px' : Math.max(x - mouseX, 10) + 'px'
const getClipPath = ({ x, y, h, mouseX, mouseY }: Positions) =>
  mouseX > x
    ? `polygon(0% 0%, 0% 100%, 100% ${(100 * (mouseY - y)) / h}%)`
    : `polygon(100% 0%, 0% ${(100 * (mouseY - y)) / h}%, 100% 100%)`

const MouseSafeArea: React.FC<MouseSafeAreaProps> = ({ parentRef }) => {
  const {
    x = 0,
    y = 0,
    height: h = 0,
    width: w = 0
  } = parentRef.current?.getBoundingClientRect?.() || {}
  const { mouseX, mouseY } = useMousePosition()
  const positions = { x, y, h, w, mouseX, mouseY }

  if (mouseX > x) {
    return
  }

  return (
    <div
      style={{
        zIndex: 1000,
        position: 'absolute',
        top: positions.y,
        right: getRight(positions),
        left: getLeft(positions),
        height: h,
        width: getWidth(positions),
        clipPath: getClipPath(positions),
        cursor: 'pointer'
      }}
    />
  )
}


export const useMousePosition = () => {
  const [position, setPosition] = useState({ mouseX: 0, mouseY: 0 })

  useEffect(() => {
    const handleMouseMove = (event: { clientX: number; clientY: number }) => {
      setPosition({
        mouseX: event.clientX,
        mouseY: event.clientY
      })
    }

    window.addEventListener('mousemove', handleMouseMove)

    return () => {
      window.removeEventListener('mousemove', handleMouseMove)
    }
  }, [])

  return position
}


export default MouseSafeArea
