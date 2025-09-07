vim9script

# autoload/buftabline.vim
# Core functionality - loaded on demand


# Script-local variables
var dirsep = fnamemodify(getcwd(), ':p')[-1 : ]
var centerbuf = winbufnr(0)
var tablineat = has('tablineat')

# Tab data structure
class TabData
    var num: number
    var pre: string = ''
    var hilite: string = ''
    var path: string = ''
    var sep: number = 0
    var label: string = ''
    var width: number = 0
endclass

# Public function to get user buffers
export def UserBuffers(): list<number>
    # help buffers are always unlisted, but quickfix buffers are not
    return filter(range(1, bufnr('$')), (_, val) => 
        buflisted(val) && getbufvar(val, "&buftype") !=? "quickfix")
enddef

# Buffer switching function for mouse support
export def SwitchBuffer(bufnum: number, clicks: number, button: string, mod: string)
    execute 'buffer ' .. bufnum
enddef

# Get buffer label
def GetBufferLabel(bufnum: number, screen_num: number): dict<any>
    var result = {
        label: '',
        path: '',
        sep: 0,
        modified: false
    }
    
    var bufpath = bufname(bufnum)
    var show_num = g:buftabline_numbers == 1
    var show_ord = g:buftabline_numbers == 2
    var show_mod = g:buftabline_indicators
    
    if strlen(bufpath) > 0
        result.path = fnamemodify(bufpath, ':p:~:.')
        result.sep = strridx(result.path, dirsep, strlen(result.path) - 2)
        result.label = result.path[result.sep + 1 : ]
        result.modified = getbufvar(bufnum, '&mod')
        
        var pre = show_num || show_ord ? string(screen_num) : ''
        if result.modified && show_mod
            pre = '+' .. pre
        endif
        if strlen(pre) > 0
            result.label = pre .. ' ' .. result.label
        endif
    elseif index(['nofile', 'acwrite'], getbufvar(bufnum, '&buftype')) > -1
        # Scratch buffer
        var num_str = show_num || show_ord ? string(screen_num) : ''
        result.label = show_mod ? '!' .. num_str : (strlen(num_str) > 0 ? num_str .. ' !' : '!')
    else
        # Unnamed file
        var mod_indicator = show_mod && getbufvar(bufnum, '&mod') ? '+' : ''
        var num_str = show_num || show_ord ? string(screen_num) : '*'
        result.label = mod_indicator .. num_str
    endif
    
    return result
enddef

# Disambiguate files with same basename
def DisambiguateTabs(tabs: list<dict<any>>)
    var path_tabs = filter(copy(tabs), (_, t) => strlen(t.path) > 0)
    var tabs_per_tail = {}
    
    # Count occurrences of each basename
    for tab in path_tabs
        var tail = tab.label
        tabs_per_tail[tail] = get(tabs_per_tail, tail, 0) + 1
    endfor
    
    # Keep adding path segments until unique
    while len(filter(copy(tabs_per_tail), (_, val) => val > 1)) > 0
        var ambiguous = copy(tabs_per_tail)
        tabs_per_tail = {}
        
        for tab in path_tabs
            if tab.sep > -1 && has_key(ambiguous, tab.label)
                tab.sep = strridx(tab.path, dirsep, tab.sep - 1)
                tab.label = tab.path[tab.sep + 1 : ]
            endif
            tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
        endfor
    endwhile
enddef

# Calculate tab widths and format labels
def CalculateTabWidths(tabs: list<dict<any>>, currentbuf: number): list<number>
    var lpad = g:buftabline_separators ? nr2char(0x23B8) : ' '
    var lpad_width = strwidth(lpad)
    var widths = [0, 0]  # [left_width, right_width]
    var current_found = false
    
    for tab in tabs
        tab.width = lpad_width + strwidth(tab.pre) + strwidth(tab.label) + 1
        tab.label = lpad .. tab.pre .. substitute(strtrans(tab.label), '%', '%%', 'g') .. ' '
        
        if tab.num == currentbuf
            widths[0] += tab.width / 2
            widths[1] += tab.width - (tab.width / 2)
            current_found = true
        elseif !current_found
            widths[0] += tab.width
        else
            widths[1] += tab.width
        endif
    endfor
    
    return widths
enddef

# Fit tabs to available columns
def FitTabsToColumns(tabs: list<dict<any>>, widths: list<number>)
    var total_width = widths[0] + widths[1]
    
    if total_width <= &columns
        return
    endif
    
    var lft = {lasttab: 0, cut: '.', indicator: '<', width: widths[0], half: &columns / 2}
    var rgt = {lasttab: -1, cut: '.$', indicator: '>', width: widths[1], half: &columns - lft.half}
    
    var oversized = []
    if lft.width < lft.half
        add(oversized, [rgt, &columns - lft.width])
    elseif rgt.width < rgt.half
        add(oversized, [lft, &columns - rgt.width])
    else
        add(oversized, [lft, lft.half])
        add(oversized, [rgt, rgt.half])
    endif
    
    for [side, budget] in oversized
        var delta = side.width - budget
        # Remove entire tabs to close the distance
        while delta >= tabs[side.lasttab].width
            delta -= remove(tabs, side.lasttab).width
        endwhile
        # Truncate the last tab to fit
        if len(tabs) > 0 && side.lasttab < len(tabs)
            var endtab = tabs[side.lasttab]
            while delta > (endtab.width - strwidth(strtrans(endtab.label)))
                endtab.label = substitute(endtab.label, side.cut, '', '')
            endwhile
            endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
        endif
    endfor
enddef

# Main render function
export def Render(): string
    var show_num = g:buftabline_numbers == 1
    var show_ord = g:buftabline_numbers == 2
    var show_mod = g:buftabline_indicators
    var lpad = g:buftabline_separators ? nr2char(0x23B8) : ' '
    
    var bufnums = UserBuffers()
    var currentbuf = winbufnr(0)
    var tabs = []
    var screen_num = 0
    
    # Build tab data
    for bufnum in bufnums
        screen_num = show_num ? bufnum : show_ord ? screen_num + 1 : 0
        
        var tab = {
            num: bufnum,
            pre: '',
            hilite: '',
            path: '',
            sep: 0,
            label: '',
            width: 0
        }
        
        # Determine highlight group
        tab.hilite = currentbuf == bufnum ? 'Current' : 
                    bufwinnr(bufnum) > 0 ? 'Active' : 'Hidden'
        
        if currentbuf == bufnum
            centerbuf = bufnum
        endif
        
        # Get buffer label info
        var label_info = GetBufferLabel(bufnum, screen_num)
        tab.label = label_info.label
        tab.path = label_info.path
        tab.sep = label_info.sep
        
        if label_info.modified && strlen(tab.path) > 0
            tab.hilite = 'Modified' .. tab.hilite
        endif
        
        # Extract pre-label for proper formatting
        if strlen(tab.path) > 0
            var pre = show_num || show_ord ? string(screen_num) : ''
            if label_info.modified && show_mod
                pre = '+' .. pre
            endif
            if strlen(pre) > 0
                tab.pre = pre .. ' '
            endif
            # Reset label to just the path part for disambiguation
            tab.label = tab.path[tab.sep + 1 : ]
        endif
        
        add(tabs, tab)
    endfor
    
    # Disambiguate same-name files
    DisambiguateTabs(tabs)
    
    # Calculate widths and format labels
    var widths = CalculateTabWidths(tabs, currentbuf)
    
    # Fit tabs to available space
    FitTabsToColumns(tabs, widths)
    
    # Clean up first tab padding
    if len(tabs) > 0
        tabs[0].label = substitute(tabs[0].label, lpad, ' ', '')
    endif
    
    # Generate tabline string
    var swallowclicks = '%' .. (1 + tabpagenr('$')) .. 'X'
    var sid = expand('<SID>')
    
    if tablineat
        return join(mapnew(tabs, (_, tab) =>
            '%#BufTabLine' .. tab.hilite .. '#' ..
            '%' .. tab.num .. '@' .. sid .. 'SwitchBuffer@' ..
            strtrans(tab.label)), '') ..
            '%#BufTabLineFill#' .. swallowclicks
    else
        return swallowclicks ..
            join(mapnew(tabs, (_, tab) =>
                '%#BufTabLine' .. tab.hilite .. '#' .. strtrans(tab.label)), '') ..
            '%#BufTabLineFill#'
    endif
enddef

# Update tabline display
export def Update(zombie: number)
    set tabline=
    
    if tabpagenr('$') > 1
        set guioptions+=e showtabline=2
        return
    endif
    
    set guioptions-=e
    
    if g:buftabline_show == 0
        set showtabline=1
        return
    elseif g:buftabline_show == 1
        # Account for BufDelete triggering before buffer is actually deleted
        var bufnums = filter(UserBuffers(), (_, val) => val != zombie)
        &g:showtabline = 1 + (len(bufnums) > 1 ? 1 : 0)
    elseif g:buftabline_show == 2
        set showtabline=2
    endif
    
    set tabline=%!buftabline#Render()
enddef

