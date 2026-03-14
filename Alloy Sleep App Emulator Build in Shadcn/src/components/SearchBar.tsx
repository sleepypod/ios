import React from 'react'
import type { JSX } from 'react/jsx-runtime'

import MagnifyingGlass from './icons/MagnifyingGlass.tsx'
import SearchInput from './SearchInput.tsx'


// Component
function SearchBar({ placeholder }: { placeholder: string }) {
            return (
                <div className={"MvkSmZJlSvlFfmyQwtB9"} style={{width:"100%"}}>
                    <MagnifyingGlass />
                    <SearchInput placeholder={placeholder} />
                </div>
            );
        }

export default SearchBar
