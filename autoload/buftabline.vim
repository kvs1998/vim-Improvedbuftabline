vim9script

# autoload/buftabline.vim
# Core functionality - loaded on demand


# Script-local variables
var dirsep = fnamemodify(getcwd(), ':p')[-1]
var centerbuf = winbufnr(0)
var tablineat = has('tablineat')
var sid = expand('<SID>')

# Public function to get user buffers for ALL tab pages
export def UserBuffers(): list<number>
    var all_buffers = []
    
    # Get all listed buffers that aren't quickfix
    for buf in range(1, bufnr('$'))
        if buflisted(buf) && getbufvar(buf, "&buftype") !=? "quickfix"
            add(all_buffers, buf)
        endif
    endfor
    
    return uniq(all_buffers)
enddef


# Buffer switching function for mouse support
# We'll modify this to not change the tabline order
export def SwitchBuffer(bufnum: number, clicks: number, button: string, mod: string)
    var found_winid = -1
    var found_tabpage = -1
    var current_tab = tabpagenr()

    # Search for the buffer in all windows across all tab pages
    for t in range(1, tabpagenr('$'))
        for w in gettabinfo(t)[0].windows
            if winbufnr(w) == bufnum
                found_winid = w
                found_tabpage = t
                break
            endif
        endfor
        if found_winid != -1
            break
        endif
    endfor

    if found_winid != -1
        # If found, jump to that tabpage first, then to the window
        if found_tabpage != current_tab
            execute 'tabnext ' .. found_tabpage
        endif
        execute found_winid .. 'wincmd w'  # Jump to the window within its tabpage
    else
        # If not found, open it in the current window
        execute 'buffer ' .. bufnum
    endif
enddef

# Get buffer label - modified to include tab number
export def GetBufferLabel(bufnum: number, screen_num: number): dict<any>
    var result = {
        label: '',
        path: '',
        sep: 0,
        modified: false,
        pre: '',
        tab_num: 0  # Track which tab this buffer is in
    }

    var bufpath = bufname(bufnum)
    var show_num = g:buftabline_numbers == 1
    var show_ord = g:buftabline_numbers == 2
    var show_mod = g:buftabline_indicators
    var is_modified = getbufvar(bufnum, '&mod')
    
    # Find which tab this buffer is in
    for t in range(1, tabpagenr('$'))
        var tabinfo = gettabinfo(t)
        if empty(tabinfo)
            continue
        endif
        
        for w in tabinfo[0].windows
            if winbufnr(w) == bufnum
                result.tab_num = t
                break
            endif
        endfor
        if result.tab_num > 0
            break
        endif
    endfor

    # Determine 'pre' (buffer/ordinal number)
    if show_num
        result.pre = string(bufnum) .. ' '
    elseif show_ord
        result.pre = string(screen_num) .. ' '
    endif

    # Determine the indicator text
    var indicator_text = ''
    if show_mod
        indicator_text = is_modified ? '+' : '-'
    endif

    # Construct the main 'label' without tab indicators (added later)
    if strlen(bufpath) > 0
        # Named file
        result.path = fnamemodify(bufpath, ':p:~:.')
        result.sep = strridx(result.path, dirsep, strlen(result.path) - 2)
        var basename = result.path[result.sep + 1 :]
        result.modified = is_modified

        var mod_prefix = strlen(indicator_text) ? '[' .. indicator_text .. '] ' : ''
        result.label = mod_prefix .. basename

    elseif index(['nofile', 'acwrite'], getbufvar(bufnum, '&buftype')) >= 0
        # Scratch buffer
        result.modified = is_modified
        var scratch_display_name = 'scratch'
        
        var specific_indicator = is_modified ? '!' : indicator_text
        var mod_prefix = strlen(indicator_text) ? '[' .. specific_indicator .. '] ' : ''
        result.label = mod_prefix .. scratch_display_name

    else
        # Unnamed file
        result.modified = is_modified
        var unnamed_display_name = '*'

        var mod_prefix = strlen(indicator_text) ? '[' .. indicator_text .. '] ' : ''
        result.label = mod_prefix .. unnamed_display_name
    endif

    return result
enddef

# Disambiguate files with same basename
export def DisambiguateTabs(tabs: list<dict<any>>)
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
            if tab.sep > -1 && has_key(ambiguous, tab.label) && ambiguous[tab.label] > 1
                tab.sep = strridx(tab.path, dirsep, tab.sep - 1)
                var prefix = matchstr(tab.label, '^\[.\]\s\+')
                var basename = tab.path[tab.sep + 1 :]
                tab.label = prefix .. (strlen(basename) ? basename : tab.path)
            endif
            tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
        endfor
    endwhile
enddef

# Calculate tab widths and positions
export def CalculateTabLayout(tabs: list<dict<any>>, currentbuf: number): dict<any>
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

    if layout.current_side is layout.lft
        layout.rgt.width = layout.lft.width
        layout.lft.width = 0
    endif

    return layout
enddef

# Fit tabs to available columns
export def FitTabsToColumns(tabs: list<dict<any>>, layout: dict<any>)
    var total_width = layout.lft.width + layout.rgt.width

    if total_width <= &columns
        return
    endif

    var oversized = []
    if layout.lft.width < layout.lft.half
        add(oversized, [layout.rgt, &columns - layout.lft.width])
    elseif layout.rgt.width < layout.rgt.half
        add(oversized, [layout.lft, &columns - layout.rgt.half])
    else
        add(oversized, [layout.lft, layout.lft.half])
        add(oversized, [layout.rgt, layout.rgt.half])
    endif

    for [side, budget] in oversized
        var delta = side.width - budget
        # Remove entire tabs to close the distance
        while delta >= tabs[side.lasttab].width
            if len(tabs) == 1 && tabs[side.lasttab].num == centerbuf
                break
            endif
            delta -= remove(tabs, side.lasttab).width
            if len(tabs) == 0
                break
            endif
        endwhile
        
        # Truncate the last tab to fit
        if len(tabs) > 0 && side.lasttab >= 0 && side.lasttab < len(tabs)
            var endtab = tabs[side.lasttab]
            var min_width = strwidth(endtab.pre)
            
            if min_width == 0 && strwidth(endtab.label) > 0 && match(endtab.label, '\v\[.\]') >= 0
                min_width = strwidth('[X] ')
            elseif min_width == 0 && match(endtab.label, '\v^\s*(\*|scratch)$') >= 0
                min_width = strwidth(match(endtab.label, '\v(\*|scratch)'))
            endif

            while delta > (endtab.width - strwidth(strtrans(endtab.label))) && strwidth(endtab.label) > min_width
                endtab.label = substitute(endtab.label, side.cut, '', '')
                delta = endtab.width - budget
            endwhile
            
            if endtab.width > budget
                 endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
            endif
        endif
    endfor
enddef

# Main render function - modified to better handle tab indicators

export def Render(): string
    var show_num = g:buftabline_numbers == 1
    var show_ord = g:buftabline_numbers == 2
    var show_tab_ind = g:buftabline_tab_indicators
    var current_tab = tabpagenr()  # Keep this for other uses
    var lpad = g:buftabline_separators ? nr2char(0x23B8) : ' '

    var bufnums = UserBuffers()
    var currentbuf = winbufnr(0)
    centerbuf = currentbuf

    if empty(bufnums)
        return '%#BufTabLineFill#' 
    endif

    var tabs = []
    var screen_num = 0

    # Build tab data
    for bufnum in bufnums
        screen_num = show_ord ? screen_num + 1 : 0

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

        # Get buffer label info - this includes the tab_num
        var label_info = GetBufferLabel(bufnum, show_num ? bufnum : show_ord ? screen_num : 0)
        tab.path = label_info.path
        tab.sep = label_info.sep
        
        # Create the prefix with tab indicator and/or buffer number
        var combined_pre = ''
        if show_tab_ind
            # Show which tab the buffer is currently visible in, or just buffer info
            var visible_in_tab = 0
            for t in range(1, tabpagenr('$'))
                for w in gettabinfo(t)[0].windows
                    if winbufnr(w) == bufnum && t == current_tab
                        visible_in_tab = t
                        break
                    endif
                endfor
            endfor
            
            if visible_in_tab > 0
                combined_pre = '%#BufTabLineCurrentTab#[T' .. visible_in_tab .. '] %#BufTabLineFill#'
            else
                combined_pre = '%#BufTabLineHidden#[--] %#BufTabLineFill#'
            endif
        endif
        if strlen(label_info.pre) > 0
            combined_pre = combined_pre .. label_info.pre
        endif
        tab.pre = combined_pre

        # Set label
        tab.label = label_info.label

        if label_info.modified && strlen(tab.path) > 0
            tab.hilite = 'Modified' .. tab.hilite
        endif

        add(tabs, tab)
    endfor

    # ... rest of the function remains the same
    # Disambiguate same-name files
    DisambiguateTabs(tabs)

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
            '%' .. tab.num .. '@' .. sid .. 'g:BufTabLineSwitchBuffer@' ..
            tab.pre .. strtrans(tab.label)), '') ..
            '%#BufTabLineFill#' .. swallowclicks
    else
        return swallowclicks ..
            join(mapnew(tabs, (_, tab) =>
                '%#BufTabLine' .. tab.hilite .. '#' .. tab.pre .. strtrans(tab.label)), '') ..
            '%#BufTabLineFill#'
    endif
enddef

# Update tabline display
export def Update(zombie: number)
    set tabline=

    var has_native_tabs = tabpagenr('$') > 1

    # Decide how to show tabline based on g:buftabline_show and native tabs
    if g:buftabline_show == 0
        &showtabline = 1 + (has_native_tabs ? 1 : 0)
        set guioptions+=e
    elseif g:buftabline_show == 1
        var bufnums_in_current_tab = UserBuffers()
        &showtabline = 1 + (len(bufnums_in_current_tab) > 1 || has_native_tabs ? 1 : 0)
        set guioptions+=e
    else  # g:buftabline_show == 2
        set showtabline=2
        if has_native_tabs
            set guioptions+=e
        else
            set guioptions-=e
        endif
    endif

    # Always set tabline to our render function
    set tabline=%!g:BufTabLineRender()
enddef