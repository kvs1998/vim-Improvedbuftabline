
vim9script

# autoload/buftabline.vim
# Core functionality - loaded on demand


# Script-local variables
var dirsep = fnamemodify(getcwd(), ':p')[-1 : ]
var centerbuf = winbufnr(0)
var tablineat = has('tablineat')
var sid = expand('<SID>')

# Public function to get user buffers for the CURRENT NATIVE TAB PAGE
export def UserBuffers(): list<number>
    var buffers_in_current_tab = []
    # Get all windows in the current tab page. gettabinfo(v:tabpagenr) returns a list
    # and the first element is a dictionary with 'windows' key.
    var current_tab_windows = gettabinfo(v:tabpagenr)[0].windows

    for winid in current_tab_windows
        var buf = winbufnr(winid)
        # Only add if it's a listed buffer and not quickfix
        if buflisted(buf) && getbufvar(buf, "&buftype") !=? "quickfix"
            add(buffers_in_current_tab, buf)
        endif
    endfor
    # Deduplicate the list, as a buffer might be open in multiple splits within the same tab.
    return uniq(buffers_in_current_tab)
enddef

# Buffer switching function for mouse support
# Exported for plugin to wrap, but also directly called via mouse
export def SwitchBuffer(bufnum: number, clicks: number, button: string, mod: string)
    var found_winid = -1
    var found_tabpage = -1

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
        if found_tabpage != v:tabpagenr
             execute 'tabnext ' .. found_tabpage
        endif
        execute found_winid .. 'wincmd w' # Jump to the window within its tabpage
    else
        # If not found (or no window is currently displaying it), open it in the current window
        execute 'buffer ' .. bufnum
    endif
enddef

# Get buffer label
export def GetBufferLabel(bufnum: number, screen_num: number): dict<any>
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

        var mod_prefix = ''
        if strlen(indicator_text) > 0
            mod_prefix = '[' .. indicator_text .. '] '
        endif
        result.label = mod_prefix .. unnamed_display_name
    endif

    return result
enddef

# Disambiguate files with same basename
export def DisambiguateTabs(tabs: list<dict<any>>)
    # Note: 'tabs' here are buftabline tabs, not native Vim tabs.
    # The labels already include tab-specific prefix if configured.
    var path_tabs = filter(copy(tabs), (_, t) => strlen(t.path) > 0)
    var tabs_per_tail = {}

    # Count occurrences of each basename (including tab indicator in label if present)
    for tab in path_tabs
        tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
    endfor

    # Keep adding path segments until unique
    while len(filter(copy(tabs_per_tail), (_, val) => val > 1)) > 0
        var ambiguous = copy(tabs_per_tail)
        tabs_per_tail = {}

        for tab in path_tabs
            # Only disambiguate if the original file path contributes to the ambiguity
            # and not just the indicator part.
            var original_basename = tab.path[tab.sep + 1 : ]
            if tab.sep > -1 && has_key(ambiguous, tab.label) && tabs_per_tail[tab.label] > 1
                tab.sep = strridx(tab.path, dirsep, tab.sep - 1)
                # Reconstruct label with prefix + new basename
                var current_prefix_len = strridx(tab.label, original_basename)
                if current_prefix_len != -1
                    tab.label = tab.label[0 : current_prefix_len] .. tab.path[tab.sep + 1 : ]
                else
                    tab.label = tab.path[tab.sep + 1 : ] # Should not happen if prefix is always prepended
                endif
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

    if layout.current_side is layout.lft  # centered buffer not seen?
        # then blame any overflow on the right side, to protect the left
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
        add(oversized, [layout.lft, &columns - layout.rgt.half]) # Use half here too for symmetry
    else
        add(oversized, [layout.lft, layout.lft.half])
        add(oversized, [layout.rgt, layout.rgt.half])
    endif

    for [side, budget] in oversized
        var delta = side.width - budget
        # Remove entire tabs to close the distance
        while delta >= tabs[side.lasttab].width
            # Ensure we don't remove the last tab if it's the only one
            if len(tabs) == 1 && tabs[side.lasttab].num == centerbuf
                break # Don't remove the current buffer if it's the only one left
            endif
            delta -= remove(tabs, side.lasttab).width
            if len(tabs) == 0
                break
            endif
        endwhile
        # Truncate the last tab to fit
        if len(tabs) > 0 && side.lasttab >= 0 && side.lasttab < len(tabs)
            var endtab = tabs[side.lasttab]
            # Keep trying to truncate until it fits or is minimal (e.g., just the indicator or number)
            # We need to be careful not to remove the indicator or number if possible.
            var min_width = strwidth(endtab.pre) # Minimum is just the number if available
            if min_width == 0 && strwidth(endtab.label) > 0 && match(endtab.label, '\v\[.\]') != -1
                min_width = strwidth('[X] ') # Min width for an indicator if no number
            endif
            if min_width == 0 && match(endtab.label, '\v^\s*(\*|scratch)$') != -1
                min_width = strwidth(match(endtab.label, '\v(\*|scratch)')) # Min width for special names
            endif

            while delta > (endtab.width - strwidth(strtrans(endtab.label))) && strwidth(endtab.label) > min_width
                endtab.label = substitute(endtab.label, side.cut, '', '')
                delta = endtab.width - budget # Recalculate delta after truncation
            endwhile
            # Add indicator only if label was actually truncated
            if endtab.width > budget
                 endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
            endif
        endif
    endfor
enddef

# Main render function
export def Render(): string
    var show_num = g:buftabline_numbers == 1
    var show_ord = g:buftabline_numbers == 2
    var show_tab_ind = g:buftabline_tab_indicators # New config
    var lpad = g:buftabline_separators ? nr2char(0x23B8) : ' '

    var bufnums = UserBuffers() # Now tab-specific
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
        
        # --- MODIFICATION: Combine tab indicator with buffer number/ordinal prefix ---
        var combined_pre = ''
        if show_tab_ind
            combined_pre = 'T' .. v:tabpagenr .. ' ' # v:tabpagenr is the current native tab page number
        endif
        if strlen(label_info.pre) > 0 # label_info.pre already contains the buffer/ordinal number + space
            combined_pre = combined_pre .. label_info.pre
        endif
        tab.pre = combined_pre # Assign the new combined prefix
        # --- END MODIFICATION ---

        # Original label (basename + mod indicator) from GetBufferLabel
        if strlen(tab.path) > 0
            tab.label = label_info.label
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

    # Disambiguate same-name files (now tab.label includes the [indicator] and basename)
    # This logic needs adjustment because tab.label now contains more than just the basename.
    # It needs to only disambiguate based on the *filename part* if there's a prefix.
    var disambiguation_needed = false
    tabs_per_tail = {} # Recalculate based on full label for potential new ambiguities

    for tab in tabs
        tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
        if tabs_per_tail[tab.label] > 1
            disambiguation_needed = true
        endif
    endfor

    if disambiguation_needed
        # Re-run DisambiguateTabs, but it needs to work on `tab.path` which is still pure path
        # The DisambiguateTabs function will adjust `tab.label` but needs to preserve the prefix
        # This is complex. For now, let's keep original DisambiguateTabs behavior
        # and assume ambiguity is mostly filename based.
        DisambiguateTabs(tabs) # This needs further refinement to handle prefixes
    endif

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
    set tabline= # Clear to force redraw

    var has_native_tabs = tabpagenr('$') > 1

    # Decide how to show tabline based on g:buftabline_show and native tabs
    if g:buftabline_show == 0 # User wants default Vim behavior (minimal custom interference)
        &showtabline = 1 + (has_native_tabs ? 1 : 0) # Show if >1 buffer OR >1 native tab
        if has_native_tabs
             set guioptions+=e
        else
             set guioptions-=e
        endif
    elseif g:buftabline_show == 1 # Auto-hide custom buftabline (if only 1 buffer in current tab)
        var bufnums_in_current_tab = UserBuffers() # Check only buffers in current tab
        &showtabline = 1 + (len(bufnums_in_current_tab) > 1 || has_native_tabs ? 1 : 0)
        if has_native_tabs
             set guioptions+=e
        else
             set guioptions-=e
        endif
    elseif g:buftabline_show == 2 # Always show custom buftabline
        set showtabline=2
        if has_native_tabs
             set guioptions+=e # Keep 'e' if native tabs are also showing
        else
             set guioptions-=e
        endif
    endif

    # Always set tabline to our render function IF showtabline is active
    # This will override Vim's default tabline content even if showtabline is 2 due to native tabs
    set tabline=%!g:BufTabLineRender()
enddef