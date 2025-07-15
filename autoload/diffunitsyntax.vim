" diffunitsyntax: Highlight word or character based diff units in diff format
"
" Last Change: 2025/07/15
" Version:     3.1
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2024-2025 Rick Howe
" License:     MIT

let s:save_cpo = &cpoptions
set cpo&vim

let s:dus = 'diffunitsyntax'

function! diffunitsyntax#DiffUnitSyntax() abort
  let du = get(b:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
  let dp = getbufvar(bufnr(), s:dus)
  if empty(dp) || dp.u != du || empty(s:dhl) || !s:CheckDiffUnit(dp)
    let dp = s:FindDiffUnitPos(du)
    call setbufvar(bufnr(), s:dus, dp)
    call s:SetDiffHighlight()
    call s:ShowDiffUnit(dp)
  endif
  call s:SetEvent()
endfunction

function! s:FindDiffUnitPos(du) abort
  let dp = {}
  " identify diff format
  let ok = 0
  for [df, pt] in [['unified', '^@@ -\d\+\(,\d\+\)\= +\d\+\(,\d\+\)\= @@'],
          \['context', '^\*\*\* \d\+\(,\d\+\)\= \*\*\*\*'],
          \['normal', '^\d\+\(,\d\+\)\=[acd]\d\+\(,\d\+\)\='],
          \['gitconflict', '^<\{7}\(.*\n\)\+=\{7}\(.*\n\)\+>\{7}\(.*\n\)\+'],
          \['diffindicator', '^[-+<>]']]
    if 0 < search(pt, 'nw', '', 100) | let ok = 1 | break | endif
  endfor
  if ok
    let op = diffutil#DiffOpt()
    let dp.u = a:du | let dp.l = [] | let dp.p = {}
    " find a list of corresponding lines to be compared
    let [cl, oc] = call('s:' . df, [])
    " follow linematch to align corresponding lines
    if has_key(op, 'linematch')
      let [z1, z2] = [[], []]
      for cx in range(min([len(cl[1]), len(cl[2])]))
        let [r1, r2] = [cl[1][cx], cl[2][cx]]
        if 1 < len(r1) || 1 < len(r2)
          let [t1, t2] = [[], []]
          for [tx, rx] in [[t1, r1], [t2, r2]]
            let tx += map(getline(rx[0], rx[-1]), 'v:val[oc:]')
          endfor
          for [i1, n1, i2, n2] in diffutil#DiffFunc(t1, t2, op)
            if 0 < n1 && 0 < n2
              for [zx, rx, ix, nx] in [[z1, r1, i1, n1], [z2, r2, i2, n2]]
                let zx += [rx[ix : ix + nx - 1]]
              endfor
            endif
          endfor
        else
          let [z1, z2] += [[r1], [r2]]
        endif
      endfor
      let [cl[1], cl[2]] = [z1, z2]
    endif
    " set a pair of diff line
    let dl = []
    for cx in range(min([len(cl[1]), len(cl[2])]))
      let [c1, c2] = [cl[1][cx], cl[2][cx]]
      for ix in range(min([len(c1), len(c2)]))
        let dl += [[c1[ix], c2[ix]]]
      endfor
    endfor
    " get a type of diff unit
    let up = (a:du == 'Char') ? '\zs' :
        \(a:du == 'Word2' || a:du ==# 'WORD') ? '\%(\s\+\|\S\+\)\zs' :
        \(a:du == 'Word3' || a:du ==# 'word') ? '\<\|\>' : '\%(\w\+\|\W\)\zs'
    " compare line and find line/column/count for each unit
    for [l1, l2] in dl
      let dp.l += [l1, l2]
      let pv = #{c: (0 < oc) ? [[l1, 1, 1], [l2, 1, 1]] : [], a: [], d: []}
      let [u1, u2] =
                  \[split(getline(l1)[oc:], up), split(getline(l2)[oc:], up)]
      for [i1, n1, i2, n2] in diffutil#DiffFunc(u1, u2, op)
        let hx = (0 < n1 && 0 < n2) ? 'c' : 'a'
        for [ux, lx, ix, nx] in [[u1, l1, i1, n1], [u2, l2, i2, n2]]
          let zl = (0 < ix) ? len(join(ux[: ix - 1], '')) : 0
          if 0 < nx
            let pv[hx] += [[lx, oc + zl + 1,
                                        \len(join(ux[ix : ix + nx - 1], ''))]]
          else
            let el = (0 < ix) ? len(matchstr(ux[ix - 1], '.$')) : 0
            let sl = (ix < len(ux)) ? len(matchstr(ux[ix], '^.')) : 0
            let pv.d += [[lx, oc + zl - el + 1, el + sl]]
          endif
        endfor
      endfor
      for hx in keys(pv)
        if !empty(pv[hx])
          let dp.p[hx] = (has_key(dp.p, hx) ? dp.p[hx] : []) + [pv[hx]]
        endif
      endfor
    endfor
  endif
  return dp
endfunction

function! s:ShowDiffUnit(dp) abort
  " link highlight and set syntax for each unit
  if empty(a:dp) || empty(a:dp.p) | return | endif
  let hp = []
  for hx in ['d', 'a', 'c']     " 'd' first not to overwrite 'a' and 'c'
    if has_key(s:dhl, hx)
      let hq = {}
      let hn = (0 < get(b:, 'DiffColors', get(g:, 'DiffColors', 1))) ?
                                                          \len(s:dhl[hx]) : 1
      if has_key(a:dp.p, hx)
        for ix in range(len(a:dp.p[hx]))
          let hl = s:dhl[hx][ix % hn]
          let hq[hl] = (has_key(hq, hl) ? hq[hl] : []) + a:dp.p[hx][ix]
        endfor
      endif
      let hp += items(hq)
    endif
  endfor
  let ln = a:dp.l[0]
  if empty(!has('nvim') ? prop_list(ln) :
                                        \filter(values(nvim_get_namespaces()),
                                      \'!empty(nvim_buf_get_extmarks(0, v:val,
                                          \[ln - 1, 0], [ln - 1, -1], {}))'))
    " syntax highlighting
    let id = 1
    while 1
      let hl = synIDattr(id, 'name')
      if empty(hl) | break | endif
      if hl =~ s:dus | call execute('syntax clear ' . hl) | endif
      let id += 1
    endwhile
    let ct = {}
    for ln in a:dp.l | let ct[ln] = empty(synstack(ln, 1)) | endfor
    for [hl, lc] in hp
      if !empty(lc)
        let hz = s:dus . hl
        call execute('highlight default link ' . hz . ' ' . hl)
        for [l, c, b] in lc
          call execute('syntax match ' . hz . ' /\%' . l . 'l\%>' . (c - 1) .
                \'c.\%<' . (c + b + 1) . 'c/' . (ct[l] ? '' : ' contained') .
                            \' containedin=diffAdded,diffRemoved,diffChanged')
        endfor
      endif
    endfor
  else
    if !has('nvim')
      " textprop highlighting
      let pz = -1
      for ln in a:dp.l
        for pr in prop_list(ln)
          if pr.type =~ s:dus
            call prop_remove(#{type: pr.type}, ln)
          else
            let pz = max([pz, prop_type_get(pr.type).priority])
          endif
        endfor
      endfor
      for [hl, lc] in hp
        if !empty(lc)
          let pt = s:dus . hl
          if empty(prop_type_get(pt))
            call prop_type_add(pt, #{highlight: hl, priority: pz + 1})
          endif
          for [l, c, b] in lc
            call prop_add(l, c, #{type: pt, length: b})
          endfor
        endif
      endfor
    else
      " extmark highlighting
      let ns = nvim_create_namespace(s:dus)
      call nvim_buf_clear_namespace(0, ns, 0, -1)
      for [hl, lc] in hp
        if !empty(lc)
          for [l, c, b] in lc
            call nvim_buf_set_extmark(0, ns, l - 1, c - 1,
                                        \#{hl_group: hl, end_col: c + b - 1})
          endfor
        endif
      endfor
    endif
  endif
endfunction

function! s:CheckDiffUnit(dp) abort
  " check if diff unit syntax is shown in current position
  if empty(a:dp) || empty(a:dp.p) | return 0 | endif
  if has('nvim') | let ns = nvim_create_namespace(s:dus) | endif
  for po in values(a:dp.p)
    if !empty(po)
      for [l, c, b] in po[0]
        if line('$') < l || col([l, '$']) - 1 < c + b - 1 | return 0 | endif
        if empty(filter(map(synstack(l, c), 'synIDattr(v:val, "name")'),
                                                        \'v:val =~ s:dus')) &&
          \(!has('nvim') ?
            \empty(filter(prop_list(l), 'v:val.type =~ s:dus')) :
            \empty(nvim_buf_get_extmarks(0, ns, [l - 1, 0], [l - 1, -1], {})))
          return 0
        endif
      endfor
    endif
  endfor
  return 1
endfunction

function! s:unified() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  let ln = 1
  while ln <= line('$') + 1
    let tx = getline(ln)
    if tx[0] == '-'
      if tx[:3] == '--- ' && getline(ln + 1)[:3] == '+++ ' | let ln += 1
      else | let dl[1] += [ln]
      endif
    elseif tx[0] == '+' | let dl[2] += [ln]
    else
      if !empty(dl[1]) && !empty(dl[2])
        for ix in [1, 2] | let cl[ix] += [dl[ix]] | endfor
      endif
      let dl = #{1: [], 2: []}
    endif
    let ln += 1
  endwhile
  return [cl, 1]
endfunction

function! s:context() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  let dx = 0
  let ln = 1
  while ln <= line('$') + 1
    let tx = getline(ln)
    if tx[:3] == '*** '
      if getline(ln + 1)[:3] == '--- ' | let ln += 1
      else | let dx = 1
      endif
    elseif tx[:3] == '--- ' | let dx = 2
    elseif 0 < dx
      if tx[0] == '!' | let dl[dx] += [ln]
      else
        for ix in [1, 2]
          if !empty(dl[ix]) | let cl[ix] += [dl[ix]] | endif
        endfor
        let dl = #{1: [], 2: []}
      endif
    endif
    let ln += 1
  endwhile
  return [cl, 2]
endfunction

function! s:normal() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  for ln in range(1, line('$') + 1)
    let tx = getline(ln)
    if tx[0] == '<' | let dl[1] += [ln]
    elseif tx[0] == '>' | let dl[2] += [ln]
    elseif tx[0] != '-'
      if !empty(dl[1]) && !empty(dl[2])
        for ix in [1, 2] | let cl[ix] += [dl[ix]] | endfor
      endif
      let dl = #{1: [], 2: []}
    endif
  endfor
  return [cl, 2]
endfunction

function! s:gitconflict() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  let dx = 0
  for ln in range(1, line('$') + 1)
    let tx = getline(ln)
    if dx == 0 && tx[:6] == '<<<<<<<' | let dx = 1
    elseif dx == 1 && tx[:6] == '=======' | let dx = 2
    elseif dx == 2 && tx[:6] == '>>>>>>>'
      for ix in [1, 2] | let cl[ix] += [dl[ix]] | let dl[ix] = [] | endfor
      let dx = 0
    elseif 0 < dx
      let dl[dx] += [ln]
    endif
  endfor
  return [cl, 0]
endfunction

function! s:diffindicator() abort
  let cl = #{1: [], 2: []} | let dl = #{1: [], 2: []}
  for ln in range(1, line('$') + 1)
    let tx = getline(ln)
    if tx[0] == '-' || tx[0] == '<' | let dl[1] += [ln]
    elseif tx[0] == '+' || tx[0] == '>' | let dl[2] += [ln]
    else
      if !empty(dl[1]) && !empty(dl[2])
        for ix in [1, 2] | let cl[ix] += [dl[ix]] | endfor
      endif
      let dl = #{1: [], 2: []}
    endif
  endfor
  return [cl, 1]
endfunction

let s:dhl = {}

function! s:SetDiffHighlight() abort
  " set a list of highlights for diff units
  if !empty(s:dhl) | return | endif
  let dh = #{c: ['DiffChange'], a: ['DiffAdd'], d: ['DiffDelPos']}
  let bx = map(dh.c + dh.a, 'synIDattr(hlID(v:val), "bg#")')
  let hl = s:dus . 'Normal'
  for fb in ['fg', 'bg']
    for cg in ['cterm', 'gui']
      call execute('highlight ' . hl . ' ' . cg . fb . '=' . fb, 'silent!')
    endfor
    let nn = synIDattr(hlID(hl), fb . '#')
    if !empty(nn) | let bx += [nn] | endif
  endfor
  call execute('highlight clear ' . hl)
  let id = 1
  while 1
    let hl = synIDattr(id, 'name')
    if empty(hl) | break | endif
    if id == synIDtrans(id)
      let bg = synIDattr(id, 'bg#')
      if !empty(bg) && index(bx, bg) == -1 &&
          \empty(filter(['bold', 'underline', 'undercurl', 'strikethrough',
                                \'reverse', 'inverse', 'italic', 'standout'],
                                            \'!empty(synIDattr(id, v:val))'))
        let dh.c += [hl] | let bx += [bg]
      endif
    endif
    let id += 1
  endwhile
  for cg in ['cterm', 'gui']
    call execute('highlight ' . dh.d[0] . ' ' . cg . '=underline', 'silent!')
  endfor
  let s:dhl = dh
endfunction

let s:dev = ['ColorScheme', 'OptionSet', 'TextChanged', 'BufDelete']

function! s:SetEvent() abort
  let bz = filter(range(1, bufnr('$')),
            \'bufloaded(v:val) && type(getbufvar(v:val, s:dus)) == type({})')
  if !empty(bz)
    let ac = []
    for en in range(len(s:dev))
      if s:dev[en] == 'ColorScheme' | let ac += [[en, '*']]
      elseif s:dev[en] == 'OptionSet' | let ac += [[en, 'diffopt']]
      else | for bn in bz | let ac += [[en, '<buffer=' . bn . '>']] | endfor
      endif
    endfor
    call execute(map(ac, '"autocmd! " . s:dus . " " . s:dev[v:val[0]] . " " .
                        \v:val[1] . " call s:HandleEvent(" . v:val[0] . ")"'))
  endif
endfunction

function! s:HandleEvent(en) abort
  let Don = {bn -> bufloaded(bn) && type(getbufvar(bn, s:dus)) == type({})}
  let Dcl = {bn -> setbufvar(bn, s:dus, {})}
  let Syn = {bn -> setbufvar(bn, '&syntax', getbufvar(bn, '&syntax'))}
  let ev = s:dev[a:en]
  if ev == 'ColorScheme'
    let s:dhl = {}
    for bn in range(1, bufnr('$'))
      if Don(bn) | call Syn(bn) | endif
    endfor
  elseif ev == 'OptionSet'
    if v:option_old != v:option_new
      for bn in range(1, bufnr('$'))
        if Don(bn) | call Dcl(bn) | call Syn(bn) | endif
      endfor
    endif
  elseif ev == 'TextChanged'
    let bn = str2nr(expand('<abuf>'))
    call Dcl(bn) | call Syn(bn)
  elseif ev == 'BufDelete'
    let bv = getbufvar(str2nr(expand('<abuf>')) , '')
    if has_key(bv, s:dus) | unlet bv[s:dus] | endif
    call s:SetEvent()
  endif
endfunction

function! diffunitsyntax#ApplyDiffUnit(fn) abort
  let lv = get(g:, 'DiffUnitSyntax', get(b:, 'DiffUnitSyntax', 1))
  if 0 < lv
    call timer_start(0, function('s:' . a:fn, [bufnr(), lv]))
  endif
endfunction

function! s:diff(bn, lv, ...) abort
  let bz = getbufinfo(a:bn)
  if !empty(bz)
    let bi = bz[0]
    let wn = (has_key(bi, 'popups') && !empty(bi.popups)) ? bi.popups[0] :
                                      \!empty(bi.windows) ? bi.windows[0] : -1
    if wn != -1
      if empty(win_gettype(wn)) || 2 <= a:lv
        call s:TriggerDiffUnit(wn)
        if !empty(win_gettype(wn))
          call s:HideOverlappedHL(wn)
        endif
      endif
    endif
  endif
endfunction

function! s:gitsigns(bn, lv, ...) abort
  for ti in gettabinfo()
    for wn in ti.windows
      if !empty(getwinvar(wn, 'gitsigns_preview')) &&
                                        \!empty(win_gettype(wn)) && 2 <= a:lv
        call s:TriggerDiffUnit(wn)
        call s:HideOverlappedHL(wn)
      endif
    endfor
  endfor
endfunction

function! s:neogit(bn, lv, ...) abort
  if bufname(a:bn) =~# '^Neogit'
    let wn = bufwinid(a:bn)
    if wn != -1
      call s:TriggerDiffUnit(wn)
      " WA: hide with clean 'Normal' to keep diff unit highlighting visible
      " line_hl_group will overlap hl_group even with higher priority
      let dp = getbufvar(a:bn, s:dus, {})
      if !empty(dp) && !empty(dp.l)
        let hl = s:dus . 'Normal'
        call execute('highlight clear ' . hl)
        let ns = nvim_create_namespace(s:dus)
        for ln in dp.l
          call nvim_buf_set_extmark(a:bn, ns, ln - 1, 0, #{line_hl_group: hl})
        endfor
      endif
    endif
  endif
endfunction

function! s:TriggerDiffUnit(wn) abort
  call win_execute(a:wn, 'call diffunitsyntax#DiffUnitSyntax()')
endfunction

function! s:HideOverlappedHL(wn) abort
  " change 'add/delete' HL to clean 'Normal' if overlapped on diff unit lines
  let bn = winbufnr(a:wn)
  let dp = getbufvar(bn, s:dus, {})
  if !empty(dp) && !empty(dp.l)
    let hl = s:dus . 'Normal'
    call execute('highlight clear ' . hl)
    if has('nvim')
      for [ns, ni] in items(nvim_get_namespaces())
        if ns != s:dus
          for ln in dp.l
            for [i, r, c, d] in nvim_buf_get_extmarks(bn, ni, [ln - 1, 0],
                                                \[ln - 1, -1], #{details: 1})
              if (0 < c || 0 < d.end_col) && d.hl_group =~? 'add\|delete'
                call nvim_buf_del_extmark(bn, ni, i)
                let d.id = i | let d.hl_group = hl
                if has_key(d, 'ns_id') | unlet d.ns_id | endif
                if !has('nvim-0.6.1') | unlet d.end_row | endif
                call nvim_buf_set_extmark(bn, ni, r, c, d)
              endif
            endfor
          endfor
        endif
      endfor
    "else
      "if empty(prop_type_get(hl))
        "call prop_type_add(hl, #{highlight: hl})
      "endif
      "for ln in dp.l
        "for pr in prop_list(ln, #{bufnr: bn})
          "if pr.type !~ s:dus
            "call prop_remove(#{bufnr: bn, type: pr.type}, ln)
            "call prop_add(ln, pr.col, #{bufnr: bn, type: hl, id: pr.id,
                                                        "\length: pr.length})
          "endif
        "endfor
      "endfor
    endif
    for ma in getmatches(a:wn)
      let po = values(filter(copy(ma), 'v:key =~ "^pos"'))
      for pv in po
        if index(dp.l, pv[0]) != -1 && ma.group =~? 'add\|delete'
          call matchdelete(ma.id, a:wn)
          call matchaddpos(hl, po, ma.priority, ma.id, #{window: a:wn})
          break
        endif
      endfor
    endfor
  endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
