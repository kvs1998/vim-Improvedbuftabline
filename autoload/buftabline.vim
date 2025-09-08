
vim9script

# autoload/buftabline.vim
# Core functionality - loaded on demand


# Script-local variables
var dirsep = fnamemodify(getcwd(), ':p')[-1 : ]
var centerbuf = winbufnr(0)
var tablineat = has('tablineat')
var sid = expand('<SID>')

# Public function to get user buffers
export def UserBuffers(): list<number>
    # help buffers are always unlisted, but quickfix buffers are not
    return filter(range(1, bufnr('$')), (_, val) => 
        buflisted(val) && getbufvar(val, "&buftype") !=? "quickfix")
enddef

# Buffer switching function for mouse support
def SwitchBuffer(bufnum: number, clicks: number, button: string, mod: string)
    execute 'buffer ' .. bufnum
enddef

# Get buffer label
# Get buffer label
def GetBufferLabel(bufnum: number, screen_num: number): dict<any>
    var result = {
        label: '',
        path: '',
        sep: 0,
        modified: false,
        pre: ''
    }

    var bufpath = bufname(bufnum)
    var show_num = g:buftabline_numbers == 1
    var show_ord = g:buftabline_numbers == 2
    var show_mod = g:buftabline_indicators
    var is_modified = getbufvar(bufnum, '&mod')

    # --- Step 1: Determine 'pre' (buffer/ordinal number) ---
    if show_num || show_ord
        result.pre = string(screen_num) .. ' '
    endif

    # --- Step 2: Determine the indicator text (e.g., '+', '!', '-') ---
    var indicator_text = ''
    if show_mod
        if is_modified
            indicator_text = '+'
        else
            indicator_text = '-' # Use '-' for unmodified if show_mod is active
        endif
    endif

    # --- Step 3: Construct the main 'label' based on buffer type ---
    if strlen(bufpath) > 0
        # Named file
        result.path = fnamemodify(bufpath, ':p:~:.')
        result.sep = strridx(result.path, dirsep, strlen(result.path) - 2)
        var basename = result.path[result.sep + 1 : ]
        result.modified = is_modified

        var mod_prefix = ''
        if strlen(indicator_text) > 0
            mod_prefix = '[' .. indicator_text .. '] '
        endif
        result.label = mod_prefix .. basename

    elseif index(['nofile', 'acwrite'], getbufvar(bufnum, '&buftype')) > -1
        # Scratch buffer
        result.modified = is_modified
        var scratch_display_name = 'scratch' # Default name for scratch buffers
        # Could make this configurable: g:buftabline_scratch_name = 'scratch'
        
        var mod_prefix = ''
        if strlen(indicator_text) > 0
            # For scratch, use '!' if modified, otherwise use the general indicator_text
            var specific_indicator = is_modified ? '!' : indicator_text
            mod_prefix = '[' .. specific_indicator .. '] '
        endif
        result.label = mod_prefix .. scratch_display_name

    else
        # Unnamed file
        result.modified = is_modified
        var unnamed_display_name = '*' # Default name for unnamed files
        # Could make this configurable: g:buftabline_unnamed_name = '*'

        var mod_prefix = ''
        if strlen(indicator_text) > 0
            mod_prefix = '[' .. indicator_text .. '] '
        endif
        result.label = mod_prefix .. unnamed_display_name
    endif

    return result
enddef

# Disambiguate files with same basename
def DisambiguateTabs(tabs: list<dict<any>>)
    var path_tabs = filter(copy(tabs), (_, t) => strlen(t.path) > 0)
    var tabs_per_tail = {}
    
    # Count occurrences of each basename
    for tab in path_tabs
        tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
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

# Calculate tab widths and positions
def CalculateTabLayout(tabs: list<dict<any>>, currentbuf: number): dict<any>
    var lpad = g:buftabline_separators ? nr2char(0x23B8) : ' '
    var lpad_width = strwidth(lpad)
    
    var layout = {
        lft: {lasttab: 0, cut: '.', indicator: '<', width: 0, half: &columns / 2},
        rgt: {lasttab: -1, cut: '.$', indicator: '>', width: 0, half: &columns - &columns / 2},
        current_side: null
    }
    
    layout.current_side = layout.lft
    
    for tab in tabs
        tab.width = lpad_width + strwidth(tab.pre) + strwidth(tab.label) + 1
        tab.label = lpad .. tab.pre .. substitute(strtrans(tab.label), '%', '%%', 'g') .. ' '
        
        if tab.num == centerbuf
            var halfwidth = tab.width / 2
            layout.lft.width += halfwidth
            layout.rgt.width += tab.width - halfwidth
            layout.current_side = layout.rgt
            continue
        endif
        layout.current_side.width += tab.width
    endfor
    
    if layout.current_side is layout.lft  # centered buffer not seen?
        # then blame any overflow on the right side, to protect the left
        layout.rgt.width = layout.lft.width
        layout.lft.width = 0
    endif
    
    return layout
enddef

# Fit tabs to available columns
def FitTabsToColumns(tabs: list<dict<any>>, layout: dict<any>)
    var total_width = layout.lft.width + layout.rgt.width
    
    if total_width <= &columns
        return
    endif
    
    var oversized = []
    if layout.lft.width < layout.lft.half
        add(oversized, [layout.rgt, &columns - layout.lft.width])
    elseif layout.rgt.width < layout.rgt.half
        add(oversized, [layout.lft, &columns - layout.rgt.width])
    else
        add(oversized, [layout.lft, layout.lft.half])
        add(oversized, [layout.rgt, layout.rgt.half])
    endif
    
    for [side, budget] in oversized
        var delta = side.width - budget
        # Remove entire tabs to close the distance
        while delta >= tabs[side.lasttab].width
            delta -= remove(tabs, side.lasttab).width
        endwhile
        # Truncate the last tab to fit
        if len(tabs) > 0 && side.lasttab >= 0 && side.lasttab < len(tabs)
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
    var lpad = g:buftabline_separators ? nr2char(0x23B8) : ' '
    
    var bufnums = UserBuffers()
    var currentbuf = winbufnr(0)
    centerbuf = centerbuf  # prevent tabline jumping around when non-user buffer current
    
    var tabs = []
    var path_tabs = []
    var tabs_per_tail = {}
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
        tab.path = label_info.path
        tab.sep = label_info.sep
        tab.pre = label_info.pre
        
        if strlen(tab.path) > 0
            tab.label = tab.path[tab.sep + 1 : ]
            tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
            add(path_tabs, tab)
        else
            tab.label = label_info.label
        endif
        
        if label_info.modified && strlen(tab.path) > 0
            tab.hilite = 'Modified' .. tab.hilite
        endif
        
        add(tabs, tab)
    endfor
    
    # Disambiguate same-name files
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
    
    # Calculate layout and format labels
    var layout = CalculateTabLayout(tabs, currentbuf)
    
    # Fit tabs to available space
    FitTabsToColumns(tabs, layout)
    
    # Clean up first tab padding
    if len(tabs) > 0
        tabs[0].label = substitute(tabs[0].label, lpad, ' ', '')
    endif
    
    # Generate tabline string
    var swallowclicks = '%' .. (1 + tabpagenr('$')) .. 'X'
    
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
        &showtabline = 1 + (len(bufnums) > 1 ? 1 : 0)
    elseif g:buftabline_show == 2
        set showtabline=2
    endif
    
    set tabline=%!g:BufTabLineRender()
enddef