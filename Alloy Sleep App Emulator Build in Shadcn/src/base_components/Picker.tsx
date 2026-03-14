import React, {
  CSSProperties,
  forwardRef,
  type RefObject,
  useCallback,
  useEffect,
  useImperativeHandle,
  useMemo,
  useReducer,
  useRef,
  useState
} from 'react'
// eslint-disable-next-line postcss-modules/no-unused-class
import CheckIcon from '../base_icons/check.svg?react'
import FilledArrowIcon from '../base_icons/filled-arrow.svg?react'
import PlusIcon from '../base_icons/plus.svg?react'
import Chevron from '../base_icons/chevron.svg?react'
import { createPortal } from 'react-dom'
import Dropdown from './Dropdown'
import Input from './Input'
import MouseSafeArea from './MouseSafeArea'
import Checkbox from './Checkbox'


interface Result {
  id: string
  name: string
  submenuItems?: ComponentResult[]
  onSelect?: () => void
  isSelected?: boolean
  selectable?: boolean
  type?: 'result'
  unavailableSelection?: boolean
}

export interface Divider {
  id: string
  name?: string
  type: 'divider'
  submenuItems?: never
}

type TextResult = (Result & { Image?: React.ComponentType }) | Divider

export type ComponentResult =
  | (Result & { Component?: React.ComponentType } & {
  Image?: React.ComponentType
})
  | Divider

type SearchResult = (ComponentResult & { searchStrings: string[]; searchId: string }) | Divider

interface CommonPickerProps {
  // You MUST give both of these full styles as if they are new components.
  // The container style MUST have a background colour that matches the app's theme.
  rowStyle: CSSProperties
  containerStyle: CSSProperties

  onClose: () => void
  onAddOption?: (name: string) => Promise<string>
  onSearchKeyDown?: (e: React.KeyboardEvent) => void
  results: TextResult[] | ComponentResult[] | SearchResult[]
  placeholder?: string
  existingIds?: string[]
  alignment: 'left' | 'right' | 'outside-left' | 'outside-right'
  containerRef?: RefObject<HTMLElement>
  initialSearch?: string
  showAddOption?: boolean
  hideExistingIds?: boolean
  hideSearch?: boolean
  emptyAddOption?: string
  mousePosition?: { x: number; y: number }
  setSvgFill?: boolean
  overlay?: boolean
  disableSearch?: boolean
  showSemiSelected?: boolean
  avoidCollision?: boolean

  // INTERNAL USE ONLY
  _setInnerSubmenuOpen?: (open: boolean) => void
}

type PickerProps =
  | (CommonPickerProps & {
  selectType?: 'multi-select'
  onResultsSelected: (ids: string[], id: string, close: boolean) => void
})
  | (CommonPickerProps & {
  selectType?: 'single'
  onResultSelected: (id: string, close: boolean) => void
})

const filterResultsBySearch = (
  results: Array<Result | Divider>,
  search: string
): Array<Result | Divider> => {
  const uniqueIds = new Set<string>()
  const filteredResults: Array<Result | Divider> = []

  if (search.length < 2) {
    const res = results.filter((result: Result | Divider) => {
      if (result.type === 'divider') {
        return search === ''
      } else {
        return 'name' in result && result.name?.toLowerCase().includes(search.toLowerCase())
      }
    })
    res.forEach((result) => {
      if ('id' in result && !uniqueIds.has(result.id)) {
        uniqueIds.add(result.id)
        filteredResults.push(result)
      }
    })
    if (filteredResults.length !== 0) {
      return filteredResults
    }
  }

  let newResults: Array<Result | Divider> = []
  results.forEach((result) => {
    const filteredResults = recursivelyFilterBySearch(result, search)
    newResults = newResults.concat(filteredResults)
  })

  newResults.forEach((result) => {
    if ('id' in result && !uniqueIds.has(result.id)) {
      uniqueIds.add(result.id)
      filteredResults.push(result)
    }
  })

  return filteredResults
}

const recursivelyFilterBySearch: (
  result: Result | Divider,
  search: string,
  callLimit?: number
) => SearchResult[] = (result: Result | Divider, search: string, callLimit: number = 20) => {
  if (callLimit === 0 || result.type === 'divider') {
    return []
  }
  let results: SearchResult[] = []
  if (result.name.toLowerCase().includes(search.toLowerCase())) {
    results.push({ ...result, searchStrings: [], searchId: result.id })
  }

  if (result.submenuItems) {
    result.submenuItems.forEach((subResult) => {
      const subResults = recursivelyFilterBySearch(subResult, search, callLimit - 1)
      results = results.concat(
        subResults
          .map((subResult) => {
            if (subResult.type === 'divider') {
              return subResult
            }
            return {
              ...subResult,
              searchId: `${result.id}-${subResult.searchId}`,
              searchStrings:
                subResult.searchStrings.length >= 1
                  ? subResult.searchStrings
                  : [result.name, ...subResult.searchStrings]
            }
          })
          .filter(Boolean)
      )
    })
  }
  return results
}

const findResultById = (results: Array<Result | Divider>, id: string): Result | undefined => {
  for (const result of results) {
    if (result.type === 'divider') {
      continue
    }
    if (result.id === id) {
      return result
    }
    if (result.submenuItems) {
      const subResult = findResultById(result.submenuItems, id)
      if (subResult) {
        return subResult
      }
    }
  }
  return undefined
}

const findResultAncestorById = (
  results: Array<Result | Divider>,
  id: string
): Result | undefined => {
  for (const result of results) {
    if (result.type === 'divider') {
      continue
    }
    if (result.id === id) {
      return result
    }
    if (result.submenuItems) {
      const subResult = findResultById(result.submenuItems, id)
      if (subResult) {
        return result
      }
    }
  }
  return undefined
}

const HierarchyPicker = (props: PickerProps) => {
  const {
    results,
    placeholder,
    existingIds,
    initialSearch,
    onClose,
    onSearchKeyDown,
    showAddOption,
    emptyAddOption,
    setSvgFill = true,
    overlay = true,
    onAddOption,
    disableSearch = false,
    showSemiSelected = false,
    _setInnerSubmenuOpen,
    rowStyle,
    containerStyle
  } = props
  const initialState: {
    search: string
    activeIndex: number
    filteredList: Array<Result | Divider>
    addingOption: boolean
  } = {
    search: initialSearch || '',
    activeIndex: 0,
    filteredList: [],
    addingOption: false
  }

  const [listReferences, setListReferences] = useState<Array<RefObject<HTMLLIElement>>>([])

  function reducer(state: typeof initialState, action: any) {
    switch (action.type) {
      case 'set_search': {
        return {
          ...state,
          search: action.payload,
          activeIndex: 0
        }
      }
      case 'set_active_index':
        if (state?.filteredList[action.payload]?.type === 'divider') {
          return state
        }
        return {
          ...state,
          activeIndex: action.payload
        }

      case 'set_initial_active_index': {
        const activeItem = state.filteredList[state.activeIndex]
        if (activeItem && activeItem.id === 'add-option') {
          return state
        }
        let index = -1
        if (lastSelectedId !== undefined) {
          const targetResult = findResultAncestorById(results, lastSelectedId)
          index = action.payload.findIndex((result: Result) => {
            return result.id === targetResult?.id
          })
        }
        if (index === -1) {
          index = action.payload.findIndex((result: Result) => {
            return existingIds?.includes(result.id)
          })
        }
        return {
          ...state,
          activeIndex: index === -1 ? 0 : index
        }
      }
      case 'filter_results': {
        const newFilteredList = filterResultsBySearch(results, state.search)
        if (showAddOption) {
          if (
            state.search &&
            !newFilteredList.some(
              (result) => result.name?.toLowerCase() === state.search.toLowerCase()
            )
          ) {
            newFilteredList.push({
              id: 'add-option',
              name: `Create '${state.search}' team`,
              Image: () => <PlusIcon />
            } as Result)
          }
          if (!state.search && emptyAddOption) {
            newFilteredList.push({
              id: 'add-option',
              name: emptyAddOption,
              Image: () => <PlusIcon />
            } as Result)
          }
        }
        if (JSON.stringify(state.filteredList) === JSON.stringify(newFilteredList)) {
          return state
        }
        return {
          ...state,
          filteredList: newFilteredList,
          activeIndex: 0
        }
      }
      default:
        return state
    }
  }

  const [addingOption, setAddingOption] = useState(false)
  const [lastSelectedId, setLastSelectedId] = useState<string | undefined>(undefined)
  const [state, dispatch] = useReducer(reducer, initialState)
  const { search, activeIndex, filteredList } = state
  const listRef = useRef(null)
  const [minWidth, setMinWidth] = useState(null)
  const pickerRef = useRef(null)

  const [updateInitialActive, setUpdateInitialActive] = useState(true)
  const [submenuOpen, setSubmenuOpen] = useState(false)

  useEffect(() => {
    const references: Array<React.RefObject<HTMLLIElement>> = []
    for (let i = 0; i < filteredList.length; i++) {
      references.push(React.createRef())
    }
    setListReferences(references)
  }, [filteredList])

  useEffect(() => {
    dispatch({ type: 'filter_results' })
  }, [search, existingIds, results])

  useEffect(() => {
    if (updateInitialActive) {
      dispatch({ type: 'set_initial_active_index', payload: filteredList })
    }
    setUpdateInitialActive(false)
  }, [filteredList, updateInitialActive])

  useEffect(() => {
    setUpdateInitialActive(true)
  }, [search, existingIds])

  useEffect(() => {
    const timer = setTimeout(() => {
      if (pickerRef.current) {
        // @ts-expect-error HiearchyPicker
        setMinWidth(`${pickerRef.current.offsetWidth}px`)
      }
    }, 50)

    return () => {
      clearTimeout(timer)
    }
  }, [])

  const onChange = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement> | { target: any; type?: any }) => {
      const inputValue = e.target.value

      if (inputValue === ' ') {
        // First entered character is a space, select the active result
        // @ts-expect-error HiearchyPicker
        listRef.current.childNodes[activeIndex]?.click()
        e.target.value = ''
        return
      }

      dispatch({ type: 'set_search', payload: inputValue })
    },
    [activeIndex]
  )

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (!listRef.current) return
      // @ts-expect-error HiearchyPicker
      const resultNodes = listRef.current.childNodes

      if (e.shiftKey) {
        // Shift switches into range select mode in grid
        e.stopPropagation()
      }

      if (submenuOpen) {
        return
      }

      switch (e.key) {
        case 'ArrowUp': {
          let newIndex = activeIndex > 0 ? activeIndex - 1 : resultNodes.length - 1
          if (filteredList[newIndex]?.type === 'divider') {
            newIndex = newIndex > 0 ? newIndex - 1 : resultNodes.length - 1
          }
          dispatch({
            type: 'set_active_index',
            payload: newIndex
          })

          e.preventDefault()
          break
        }
        case 'ArrowDown': {
          let newIndex = activeIndex === resultNodes.length - 1 ? 0 : activeIndex + 1
          if (filteredList[newIndex]?.type === 'divider') {
            newIndex = newIndex === resultNodes.length - 1 ? 0 : newIndex + 1
          }
          dispatch({
            type: 'set_active_index',
            payload: newIndex
          })

          e.preventDefault()
          break
        }
        case 'Enter':
          e.stopPropagation()
          // @ts-expect-error HiearchyPicker
          listRef.current.childNodes[activeIndex]?.click()
          break

        case 'Escape':
          e.stopPropagation()
          onClose()
          break

        default:
          /* Check if the key pressed is a printable character */
          if (/^[a-z0-9]$/i.test(e.key)) {
            dispatch({ type: 'set_active_index', payload: 0 })
          }
      }
    },
    [activeIndex, filteredList, onClose, submenuOpen]
  )

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown)
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [handleKeyDown])

  const updateActiveIndexOnHover = useCallback(
    (e: React.MouseEvent) => {
      if (listRef.current) {
        // @ts-expect-error HiearchyPicker
        listRef.current.childNodes.forEach((node: any, index: any) => {
          if (node.contains(e.target)) {
            dispatch({ type: 'set_active_index', payload: index })
          }
        })
      }
    },
    [listRef]
  )

  const onResultSelected = useCallback(
    async (result: string | { onSelect: () => void }) => {
      // Check if result is selectable

      if (typeof result === 'string') {
        const resultObject = findResultById(results, result)
        if (resultObject?.selectable === false) {
          return
        }
      }

      if (addingOption) {
        return
      }
      if (typeof result !== 'string') {
        result.onSelect()
        return
      }
      if (result === 'add-option') {
        setAddingOption(true)
        // @ts-expect-error HiearchyPicker
        result = await props.onAddOption(state.search)
        setAddingOption(false)
      }
      const { selectType } = props
      if (selectType === 'multi-select') {
        if (existingIds?.includes(result)) {
          const newSelectedIds = new Set(existingIds)
          newSelectedIds.delete(result)
          props.onResultsSelected(Array.from(newSelectedIds), result, false)
        } else {
          props.onResultsSelected([...(existingIds || []), result], result, false)
        }
        setLastSelectedId(result)
      } else {
        // @ts-expect-error HiearchyPicker
        props.onResultSelected(result, true)
      }
    },
    [addingOption, props, results, state.search, existingIds]
  )

  const onResultsSelected = useCallback(
    async (ids: string[]) => {
      // Bit hacky, we check the difference between existing ids and new ids and pass result to onResultSelected
      const existingIdSet = new Set(existingIds ?? [])
      const newIds = new Set(ids)

      const diffIds: any[] = []
      for (const id of existingIdSet) {
        if (!newIds.has(id)) {
          diffIds.push(id)
        }
      }
      for (const id of newIds) {
        if (!existingIdSet.has(id)) {
          diffIds.push(id)
        }
      }
      // This should never have more than one element
      await onResultSelected(diffIds[0])
    },
    [existingIds, onResultSelected]
  )

  const exisitingIdArray = useMemo(() => {
    return existingIds || []
  }, [existingIds])

  return (
    <>
      <Dropdown
        onClose={onClose}
        buttonRef={props.containerRef}
        mousePosition={props.mousePosition}
        alignment={props.alignment}
        avoidCollision={props.avoidCollision}
        overlay={overlay}
        extraRoundedCorners
        submenuShift={!!_setInnerSubmenuOpen} // As part of a submenu this prop will be defined
      >
        <div
          style={{
            minWidth: '122px',
            maxWidth: 'unset',
            ...(minWidth ? { minWidth } : {}),
            ...containerStyle
          }}
          onMouseMove={updateActiveIndexOnHover}
          ref={pickerRef}
        >
          {!disableSearch && (
            <div
              style={props.hideSearch ? {
                height: 0,
                opacity: 0,
                zIndex: -1,
                position: 'relative',
                border: 0,
                width: 0
              } : {
                opacity: 1,
                height: '40px'
              }}
            >
              <Input
                appearance={'picker'}
                autoFocus
                placeholder={placeholder || 'Search...'}
                onChange={onChange}
                value={search}
                onKeyDown={onSearchKeyDown}
              />
            </div>
          )}

          <ul style={{
            height: '100%',
            display: 'flex',
            flexDirection: 'column',
            padding: '0 4px',
            maxHeight: 'min(60dvh, 1600px)',
            overflowY: 'auto',
            overflowX: 'hidden'
          }} ref={listRef}>
            {filteredList.length === 0 && (
              <span style={{
                borderRadius: '4px',
                boxSizing: 'border-box',
                height: '100%',
                display: 'flex',
                gap: '24px',
                minHeight: '32px',
                padding: '5px 8px',
                alignItems: 'center',
                justifyContent: 'space-between',
                cursor: 'inherit',
                transition: 'background 80ms ease',
                flexShrink: 0,
                maxWidth: '180px',
                marginTop: '5px',
                marginBottom: '5px'
              }}>No results found</span>
            )}
            {filteredList.map(
              (result: TextResult | ComponentResult | SearchResult, index: number) => {
                return result.id === 'add-option' ? (
                  <AddOptionResult
                    result={result}
                    isActive={activeIndex === index}
                    onResultSelected={async () => {
                      setAddingOption(true)
                      // @ts-expect-error HiearchyPicker
                      result.id = await onAddOption(state.search)
                      setAddingOption(false)
                      await onResultSelected(result.id)
                    }}
                    addingOption={addingOption}
                    key={result.id}
                    ref={listReferences[index]}
                  />
                ) : (
                  <PickerResult
                    key={'searchId' in result ? result.searchId : result.id}
                    result={result}
                    isActive={activeIndex === index}
                    onResultSelected={onResultSelected}
                    onResultsSelected={onResultsSelected}
                    isSelected={!!existingIds?.includes(result.id)}
                    selectType={props.selectType ?? 'single'}
                    setSvgFill={setSvgFill}
                    existingIds={exisitingIdArray}
                    ref={listReferences[index]}
                    showSemiSelected={showSemiSelected}
                    setMenuOpen={(open: boolean) => {
                      setSubmenuOpen(open)
                      _setInnerSubmenuOpen?.(open)
                    }}
                    rowStyle={rowStyle}
                    containerStyle={containerStyle}
                  />
                )
              }
            )}
          </ul>
        </div>
      </Dropdown>
      {!!_setInnerSubmenuOpen &&
        !submenuOpen &&
        createPortal(<MouseSafeArea parentRef={listRef} />, document.body)}
    </>
  )
}

interface PickerResultProps {
  result: ComponentResult | SearchResult
  isActive: boolean
  selectType: 'multi-select' | 'single'
  onResultSelected: (id: string) => void
  onResultsSelected: (ids: string[]) => void
  isSelected: boolean
  setSvgFill?: boolean
  setMenuOpen: (open: boolean) => void
  existingIds: string[]
  showSemiSelected?: boolean
  rowStyle?: CSSProperties
  containerStyle?: CSSProperties
}

const PickerResult = forwardRef<HTMLLIElement, PickerResultProps>((props, ref) => {
  const {
    result,
    isActive,
    selectType,
    isSelected,
    setMenuOpen,
    onResultSelected,
    existingIds,
    onResultsSelected,
    showSemiSelected,
    rowStyle,
    containerStyle
  } = props

  const [submenuOpen, setSubmenuOpen] = useState(false)
  const [subSubmenuOpen, setSubSubmenuOpen] = useState(false)
  const dontCloseSubmenu = useRef(false)
  const containerRef = useRef(null)

  useImperativeHandle(ref, () => {
    // @ts-expect-error HiearchyPicker
    return { ...containerRef.current }
  })

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (subSubmenuOpen) {
        return
      }
      if (
        e.key === 'ArrowRight' &&
        result.type !== 'divider' &&
        result.submenuItems &&
        !submenuOpen &&
        isActive
      ) {
        setMenuOpen(true)
        setSubmenuOpen(true)
        e.stopPropagation()
      } else if (e.key === 'ArrowLeft' && submenuOpen) {
        setMenuOpen(false)
        setSubmenuOpen(false)

        e.stopPropagation()
      }
    },
    [subSubmenuOpen, result, submenuOpen, isActive, setMenuOpen]
  )

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown)
    return () => {
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [handleKeyDown])

  useEffect(() => {
    if (isActive) {
      // @ts-expect-error HiearchyPicker
      containerRef?.current?.focus()
    } else {
      if (dontCloseSubmenu.current) {
        dontCloseSubmenu.current = false
      } else {
        setSubmenuOpen(false)
      }
      setSubSubmenuOpen(false)
      setMenuOpen(false)
    }
  }, [isActive, containerRef, setMenuOpen, selectType])

  const selectedState = useMemo(() => {
    if (result.type === 'divider') {
      return false
    }
    if (showSemiSelected) {
      if (result.submenuItems) {
        if (result.submenuItems.every((subResult) => existingIds.includes(subResult.id))) {
          return true
        }
        if (result.submenuItems.some((subResult) => existingIds.includes(subResult.id))) {
          return 'indeterminate'
        }
        return false
      }
    }
    return isSelected
  }, [existingIds, isSelected, result?.submenuItems, result.type, showSemiSelected])

  if (result.type === 'divider') {
    if (result.name) {
      return (
        <h5 style={{
          minWidth: '100%',
          padding: '8px 0 0 6px',
          flexShrink: 0,
          paddingBottom: !result.name ? 5 : 0
        }}>
          {result.name}
        </h5>
      )
    } else {
      return <hr style={{
        margin: '4px -4px',
        borderRadius: '0px',
        height: '1px',
        minHeight: '1px'
      }} />
    }
  }

  return (
    <li
      key={result.id}
      style={{
        borderRadius: '4px',
        boxSizing: 'border-box',
        height: '100%',
        display: 'flex',
        gap: '24px',
        minHeight: '32px',
        padding: '5px 8px',
        alignItems: 'center',
        justifyContent: 'space-between',
        cursor: result.unavailableSelection ? 'default' : 'pointer',
        transition: 'background 80ms ease',
        flexShrink: 0,
        marginTop: '5px',
        marginBottom: '5px',
        opacity: result.unavailableSelection ? 0.5 : 1,
        pointerEvents: result.unavailableSelection ? 'none' : 'auto',
        ...rowStyle
      }}
      onClick={() => {
        if (result.unavailableSelection) {
          return
        }
        result.onSelect ? result.onSelect?.() : onResultSelected(result.id)
      }}
      ref={containerRef}
      onMouseMove={() => {
        if (result.submenuItems) {
          setSubmenuOpen(true)
          setMenuOpen(true)
        }
      }}
    >
      <div style={{
        maxWidth: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'left',
        gap: '8px',
        whiteSpace: 'nowrap'
      }}>
        {selectType === 'multi-select' && result.selectable !== false && (
          <Checkbox
            checked={selectedState}
            type={'indeterminate'}
          />
        )}
        {!('Image' in result) && !('Component' in result) && (
          <PickerTextRenderer
            text={result.name}
            searchStrings={'searchStrings' in result ? result.searchStrings : undefined}
          />
        )}
        {'Image' in result && (
          <>
            <div style={{
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}>
              {
                // @ts-expect-error HiearchyPicker
                <result.Image />
              }
            </div>
            <PickerTextRenderer
              text={result.name}
              searchStrings={'searchStrings' in result ? result.searchStrings : undefined}
            />
          </>
        )}
        {'Component' in result && (
          <>
            {
              // @ts-expect-error HiearchyPicker
              <result.Component />
            }
          </>
        )}{' '}
      </div>
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'left',
        gap: '8px',
        whiteSpace: 'nowrap'
      }}>
        {result.isSelected && <CheckIcon style={{ width: '13px' }} />}
        {result.submenuItems && <FilledArrowIcon />}
      </div>
      {submenuOpen && (
        <HierarchyPicker
          onClose={() => {
            setSubmenuOpen(false)
            setMenuOpen(false)
            setSubSubmenuOpen(false)
          }}
          results={result.submenuItems ?? []}
          alignment={'outside-right'}
          hideSearch={true}
          existingIds={existingIds}
          selectType={selectType}
          showSemiSelected={showSemiSelected}
          onResultSelected={(id: string) => {
            setSubmenuOpen(false)
            setSubSubmenuOpen(false)
            setMenuOpen(false)
            onResultSelected(id)
          }}
          onResultsSelected={(ids: string[]) => {
            onResultsSelected(ids)
            dontCloseSubmenu.current = true
          }}
          containerRef={containerRef}
          overlay={false}
          _setInnerSubmenuOpen={setSubSubmenuOpen}
          disableSearch={true}
          rowStyle={rowStyle}
          containerStyle={containerStyle}
        />
      )}
    </li>
  )
})

const PickerTextRenderer = (props: { text: string; searchStrings?: string[] }) => {
  if (props.searchStrings) {
    return (
      <div style={{
        display: 'flex',
        justifyContent: 'flex-start',
        alignItems: 'center',
        gap: '4px'
      }}>
        {props.searchStrings.map((searchString, index) => {
          return (
            <React.Fragment key={index}>
              <span style={{ opacity: 0.8 }}>{searchString}</span>
              <Chevron style={{
                transform: 'rotate(90deg)',
                width: '12.5px',
                height: '12.5px'
              }} />
            </React.Fragment>
          )
        })}
        <span>{props.text}</span>
      </div>
    )
  }
  return <span>{props.text}</span>
}

interface AddOptionResultProps {
  result: ComponentResult
  isActive: boolean
  onResultSelected: () => void
  addingOption: boolean
}

const AddOptionResult = forwardRef<HTMLLIElement, AddOptionResultProps>((props, ref) => {
  const { result, isActive, onResultSelected, addingOption } = props
  return (
    <li
      key={'add-option'}
      style={{
        borderRadius: '4px',
        boxSizing: 'border-box',
        height: '100%',
        display: 'flex',
        gap: '24px',
        minHeight: '32px',
        padding: '5px 8px',
        alignItems: 'center',
        justifyContent: 'space-between',
        cursor: 'pointer',
        transition: 'background 80ms ease',
        flexShrink: 0,
        marginTop: '5px',
        marginBottom: '5px',
        opacity: addingOption ? 0.8 : 1,
        pointerEvents: addingOption ? 'none' : 'auto'
      }}
      onClick={onResultSelected}
      ref={ref}
    >
      <div style={{
        maxWidth: '100%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'left',
        gap: '8px',
        whiteSpace: 'nowrap'
      }}>
        <div style={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          width: '16px'
        }}>
          <PlusIcon />
        </div>
        <span>{result.name}</span>
      </div>
    </li>
  )
})

export default HierarchyPicker
