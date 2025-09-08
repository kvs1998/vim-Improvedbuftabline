vim9script

# plugin/buftabline.vim
# Main plugin file - minimal initialization

import '../autoload/buftabline.vim'


if v:version < 900
    echoerr printf('Vim 9 is required for buftabline vim9 version (this is only %d.%d)', v:version / 100, v:version % 100)
    finish
endif

# Prevent duplicate loading
if get(g:, 'loaded_buftabline', 0)
    finish
endif
g:loaded_buftabline = 1

# Save and restore compatibility options
var save_cpo = &cpo
set cpo&vim

# Configuration variables with defaults
g:buftabline_numbers = get(g:, 'buftabline_numbers', 0)
g:buftabline_indicators = get(g:, 'buftabline_indicators', 0)
g:buftabline_separators = get(g:, 'buftabline_separators', 0)
g:buftabline_show = get(g:, 'buftabline_show', 2)
g:buftabline_plug_max = get(g:, 'buftabline_plug_max', 10)

# Setup highlight groups
def SetupHighlights()
    hi default link BufTabLineCurrent         TabLineSel
    hi default link BufTabLineActive          PmenuSel
    hi default link BufTabLineHidden          TabLine
    hi default link BufTabLineFill            TabLineFill
    hi default link BufTabLineModifiedCurrent BufTabLineCurrent
    hi default link BufTabLineModifiedActive  BufTabLineActive
    hi default link BufTabLineModifiedHidden  BufTabLineHidden
enddef

# Initialize highlights
SetupHighlights()

# Global wrapper functions for backward compatibility
def g:BufTabLineUserBuffers(): list<number>
    return buftabline.UserBuffers()
enddef

def g:BufTabLineRender(): string
    return buftabline.Render()
enddef

def g:BufTabLineUpdate(zombie: number)
    buftabline.Update(zombie)
enddef

# Setup autocommands
augroup BufTabLine
    autocmd!
    autocmd VimEnter  * call g:BufTabLineUpdate(0)
    autocmd TabEnter  * call g:BufTabLineUpdate(0)
    autocmd BufAdd    * call g:BufTabLineUpdate(0)
    autocmd FileType qf call g:BufTabLineUpdate(0)
    autocmd BufDelete * call g:BufTabLineUpdate(str2nr(expand('<abuf>')))
    autocmd ColorScheme * call SetupHighlights()
augroup END

# Create plug mappings
def CreatePlugMappings()
    var plug_range = range(1, g:buftabline_plug_max)
    if g:buftabline_plug_max > 0
        add(plug_range, -1)
    endif

    for n in plug_range
        var b = n == -1 ? -1 : n - 1
        execute printf("noremap <silent> <Plug>BufTabLine.Go(%d) :<C-U>exe 'b'.get(g:BufTabLineUserBuffers(),%d,'')<cr>", n, b)
    endfor
enddef

CreatePlugMappings()

# User commands
command! -nargs=0 BufTabLineRefresh call g:BufTabLineUpdate(0)
command! -nargs=0 BufTabLineToggleNumbers g:buftabline_numbers = (g:buftabline_numbers + 1) % 3 | BufTabLineRefresh
command! -nargs=0 BufTabLineToggleIndicators g:buftabline_indicators = !g:buftabline_indicators | BufTabLineRefresh


# This will be set by buftabline.Update anyway, but good to have a default
set tabline=%!g:BufTabLineRender()
