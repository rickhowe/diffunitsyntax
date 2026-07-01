" diffunitsyntax: Highlight word or character based diff units in diff format
"
" Last Change: 2026/07/01
" Version:     3.3
" Author:      Rick Howe (Takumi Ohtani) <rdcxy754@ybb.ne.jp>
" Copyright:   (c) 2024-2026 Rick Howe
" License:     MIT

let s:save_cpo = &cpoptions
set cpo&vim

let s:dus = 'diffunitsyntax'

function! diffunitsyntax#DiffUnitSyntax() abort
  "let du = matchstr(&diffopt, 'inline:\zs[^,]\+')
  "if empty(du)
    let du = get(b:, 'DiffUnit', get(g:, 'DiffUnit', 'Word1'))
  "endif
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
  "if a:du != 'none'
    " identify diff format & find a list of corresponding changed lines
    let [cl, oc] = s:FindChangedLines()
    if !empty(cl)
      let op = diffutil#DiffOpt()
      let dp.u = a:du | let dp.l = [] | let dp.p = {}
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
            for [i1, c1, i2, c2] in diffutil#DiffFunc(t1, t2, op)
              if 0 < c1 && 0 < c2
                for [zx, rx, ix, cx] in [[z1, r1, i1, c1], [z2, r2, i2, c2]]
                  let zx += [rx[ix : ix + cx - 1]]
                endfor
              endif
            endfor
          else
            let [z1, z2] += [[r1], [r2]]
          endif
        endfor
        let [cl[1], cl[2]] = [z1, z2]
        unlet op['linematch']
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
      let up = (a:du == 'Word1') ? '\%(\w\+\|\W\)\zs' :
              \(a:du == 'Word2' || a:du ==# 'WORD') ? '\%(\s\+\|\S\+\)\zs' :
              \(a:du == 'Word3' || a:du ==# 'word') ? '\<\|\>' : '\zs'
      " compare line and find line/column/count for each unit
      for [l1, l2] in dl
        let dp.l += [l1, l2]
        let pv = #{c: (0 < oc) ? [[l1, 1, 1], [l2, 1, 1]] : [], a: [], d: []}
        let [u1, u2] =
                  \[split(getline(l1)[oc:], up), split(getline(l2)[oc:], up)]
        let ic = diffutil#DiffFunc(u1, u2, op)
        "if a:du == 'simple' && 1 < len(ic)
          "let ic = [[ic[0][0], ic[-1][0] + ic[-1][1] - ic[0][0],
                                "\ic[0][2], ic[-1][2] + ic[-1][3] - ic[0][2]]]
        "endif
        for [i1, c1, i2, c2] in ic
          let hx = (0 < c1 && 0 < c2) ? 'c' : 'a'
          for [ux, lx, ix, cx] in [[u1, l1, i1, c1], [u2, l2, i2, c2]]
            let zl = (0 < ix) ? len(join(ux[: ix - 1], '')) : 0
            if 0 < cx
              let pv[hx] += [[lx, oc + zl + 1,
                                        \len(join(ux[ix : ix + cx - 1], ''))]]
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
  "endif
  return dp
endfunction

function! s:ShowDiffUnit(dp) abort
  if empty(a:dp) || empty(a:dp.p) | return | endif
  " get a 'containedin' syntax shown in the line
  let ct = {}
  for l in a:dp.l | let ct[l] = synIDattr(synID(l, 1, 1), 'name') | endfor
  " set highlight and position for each unit
  let hp = []
  for hx in ['d', 'a', 'c']     " 'd' first not to overwrite 'a' and 'c'
    if has_key(s:dhl, hx)
      let hq = {}
      let hn = (0 < get(b:, 'DiffColors', get(g:, 'DiffColors', 1))) ?
                                                          \len(s:dhl[hx]) : 1
      if has_key(a:dp.p, hx)
        for ix in range(len(a:dp.p[hx]))
          for [l, c, b] in a:dp.p[hx][ix]
            let hl = s:dhl[hx][(hx != 'd') ? ix % hn :
                                            \!empty(ct[l]) ? ct[l] : 'Normal']
            let hq[hl] = (has_key(hq, hl) ? hq[hl] : []) + [[l, c, b]]
          endfor
        endfor
      endif
      let hp += items(hq)
    endif
  endfor
  " delete (1)inline and (2)bg/attr-enabled textprop/extmark/match hl on dp.l,
  " when diff syntax is not applied, add (2) back as diff syntax hl
  let ds = exists('b:current_syntax') && b:current_syntax == 'diff' ||
          \execute('syntax list diffAdded', 'silent!') =~? 'diffAdded.*match'
  if !has('nvim')
    for ln in a:dp.l
      for pr in prop_list(ln)
        if pr.type !~? s:dus
          let pt = prop_type_get(pr.type)
          let pt.highlight = s:FindDiffSyntax(pt.highlight)
          if !empty(pt.highlight)
            call prop_remove(#{id: pr.id, type: pr.type}, pr.lnum)
            if !ds && 0 < hlID(pt.highlight)
              if empty(prop_type_get(pt.highlight))
                call prop_type_add(pt.highlight, pt)
              endif
              call prop_add(pr.lnum, pr.col, #{id: pr.id, type: pt.highlight})
            endif
          endif
        endif
      endfor
    endfor
  else
    for [ns, ni] in items(nvim_get_namespaces())
      if ns != s:dus
        for ln in a:dp.l
          for [i, r, c, d] in nvim_buf_get_extmarks(0, ni, [ln - 1, 0],
                                                \[ln - 1, -1], #{details: 1})
            if has_key(d, 'hl_group')
              let d.hl_group = s:FindDiffSyntax(d.hl_group)
              if !empty(d.hl_group)
                call nvim_buf_del_extmark(0, ni, i)
                if !ds && 0 < hlID(d.hl_group)
                  if has_key(d, 'ns_id') | unlet d.ns_id | endif
                  let d.id = i
                  call nvim_buf_set_extmark(0, ni, r, c, d)
                endif
              endif
            endif
          endfor
        endfor
      endif
    endfor
  endif
  for ma in getmatches()
    if ma.group !~? s:dus && (ds || !empty(s:FindDiffSyntax(ma.group)))
      for pv in values(filter(copy(ma), 'v:key =~? "^pos"'))
        if index(a:dp.l, pv[0]) != -1
          call matchdelete(ma.id)
          break
        endif
      endfor
    endif
  endfor
  " show diff unit highlighting
  if ds
    let id = 1
    while 1
      let hl = synIDattr(id, 'name')
      if empty(hl) | break | endif
      if hl =~? s:dus | call execute('syntax clear ' . hl) | endif
      let id += 1
    endwhile
    for [hl, lc] in hp
      if !empty(lc)
        if hl !~? s:dus
          call execute('highlight link ' . (s:dus . hl) . ' ' . hl)
          let hl = s:dus . hl
        endif
        for [l, c, b] in lc
          call execute('syntax match ' . hl .
                          \' /\%' . l . 'l\%' . c . 'c.*\%' . (c + b) . 'c/' .
                    \(!empty(ct[l]) ? ' contained containedin=' . ct[l] : ''))
        endfor
      endif
    endfor
  else
    if !has('nvim')
      let pz = -1
      for ln in a:dp.l
        for pr in prop_list(ln)
          if pr.type =~? s:dus
            call prop_remove(#{type: pr.type}, ln)
          else
            let pz = max([pz, prop_type_get(pr.type).priority])
          endif
        endfor
      endfor
      for [hl, lc] in hp
        if !empty(lc)
          let pt = (hl =~? s:dus) ? hl : s:dus . hl
          if empty(prop_type_get(pt))
            call prop_type_add(pt, #{highlight: hl, priority: pz + 1})
          endif
          for [l, c, b] in lc
            call prop_add(l, c, #{type: pt, length: b})
          endfor
        endif
      endfor
    else
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
                                                      \'v:val =~? s:dus')) &&
          \empty(!has('nvim') ? filter(prop_list(l), 'v:val.type =~? s:dus') :
                  \nvim_buf_get_extmarks(0, ns, [l - 1, 0], [l - 1, -1], {}))
          return 0
        endif
      endfor
    endif
  endfor
  return 1
endfunction

function! s:FindChangedLines() abort
  let cl = {}
  for [df, pt, oc] in [
    \['unified', '^@@ -\d\+\(,\d\+\)\= +\d\+\(,\d\+\)\= @@', 1],
    \['context', '^\*\{15}.*\n\*\{3} \(.*\n\)\{-1,}-\{3} \(.*\n\)\{-1,}', 2],
    \['normal', '^\d\+\(,\d\+\)\=[acd]\d\+\(,\d\+\)\=', 2],
    \['gitconflict', '^<\{7}\(.*\n\)\+=\{7}\(.*\n\)\+>\{7}\(.*\n\)\+', 0],
    \['diffindicator', '\(^[-<].*\n\)\+\(^[+>].*\n\)\+', 1]]
    if 0 < search(pt, 'nw', '', 100)
      for ix in [1, 2] | let cl[ix] = [[]] | endfor
      if df == 'unified'
        for ln in range(1, line('$'))
          let tx = getline(ln)
          if tx[0] == '-' && tx[:3] != '--- ' | let cl[1][-1] += [ln]
          elseif tx[0] == '+' && tx[:3] != '+++ ' | let cl[2][-1] += [ln]
          elseif tx[0] != '\'
            for ix in [1, 2] | let cl[ix] += [[]] | endfor
          endif
        endfor
      elseif df == 'context'
        let cx = 0
        for ln in range(1, line('$'))
          let tx = getline(ln)
          if tx =~ '^\*\{15}' | let cx = 0
            for ix in [1, 2]
              if !empty(cl[ix][-1]) | let cl[ix] += [[]] | endif
            endfor
          elseif tx =~ '^\*\{3} \d\+\(,\d\+\)\= \*\{4}' | let cx = 1
          elseif tx =~ '^-\{3} \d\+\(,\d\+\)\= -\{4}' | let cx = 2
          elseif tx[0] != '\' && 0 < cx
            if tx[0] == '!' | let cl[cx][-1] += [ln]
            elseif !empty(cl[cx][-1]) | let cl[cx] += [[]]
            endif
          endif
        endfor
      elseif df == 'normal'
        for ln in range(1, line('$'))
          let tx = getline(ln)
          if tx =~ '^\d\+' | for ix in [1, 2] | let cl[ix] += [[]] | endfor
          elseif tx[0] == '<' | let cl[1][-1] += [ln]
          elseif tx[0] == '>' | let cl[2][-1] += [ln]
          endif
        endfor
      elseif df == 'gitconflict'
        let cx = 0
        for ln in range(1, line('$'))
          let tx = getline(ln)
          if cx == 0 && tx[:6] == '<<<<<<<' | let cx = 1
            for ix in [1, 2] | let cl[ix] += [[]] | endfor
          elseif cx == 1 && tx[:6] == '=======' | let cx = 2
          elseif cx == 2 && tx[:6] == '>>>>>>>' | let cx = 0
          elseif 0 < cx | let cl[cx][-1] += [ln]
          endif
        endfor
      elseif df == 'diffindicator'
        for ln in range(1, line('$'))
          let tx = getline(ln)
          if tx[0] == '-' || tx[0] == '<' | let cl[1][-1] += [ln]
          elseif tx[0] == '+' || tx[0] == '>' | let cl[2][-1] += [ln]
          else | for ix in [1, 2] | let cl[ix] += [[]] | endfor
          endif
        endfor
      endif
      for cx in range(len(cl[1]) - 1, 0, -1)
        if empty(cl[1][cx]) || empty(cl[2][cx])
          for ix in [1, 2] | unlet cl[ix][cx] | endfor
        endif
      endfor
      break
    endif
  endfor
  return [cl, oc]
endfunction

let s:dhl = {}

function! s:SetDiffHighlight() abort
  " set a list of highlights for diff units
  if !empty(s:dhl) | return | endif
  let dh = {}
  " for added unit
  let dh.a = ['DiffAdd']
  " for changed unit, select hl in which bg and no attr are defined
  let dh.c = ['DiffChange']
  let bx = map(dh.c + dh.a, 'synIDattr(hlID(v:val), "bg#")')
  for fb in ['fg', 'bg']
    let nn = synIDattr(hlID('Normal'), fb . '#')
    if !empty(nn) | let bx += [nn] | endif
  endfor
  let id = 1
  while 1
    let hl = synIDattr(id, 'name')
    if empty(hl) | break | endif
    if hl !~? s:dus && id == synIDtrans(id)
      let bg = synIDattr(id, 'bg#')
      if !empty(bg) && index(bx, bg) == -1 && empty(filter(['bold', 'italic',
                  \'reverse', 'inverse', 'standout', 'underline', 'undercurl',
                          \'strikethrough'], '!empty(synIDattr(id, v:val))'))
        let dh.c += [hl] | let bx += [bg]
      endif
    endif
    let id += 1
  endwhile
  " for deleted unit, add bold/underline to diff syntax hl and define them
  let dh.d = {}
  for hl in ['Normal', 'diffAdded', 'diffRemoved', 'diffChanged']
    let id = synIDtrans(hlID(hl))
    if 0 < id
      let zz = []
      for cg in ['cterm', 'gui']
        let zz += [cg . '=bold,underline']
        if hl != 'Normal'
          for fb in ['fg', 'bg']
            let nn = synIDattr(id, fb, cg)
            if !empty(nn) | let zz += [cg . fb . '=' . nn] | endif
          endfor
        endif
      endfor
      let dh.d[hl] = s:dus . synIDattr(id, 'name')
      call execute('highlight ' . dh.d[hl] . ' ' . join(zz), 'silent!')
    else
      let dh.d[hl] = dh.d['Normal']
    endif
  endfor
  let s:dhl = dh
endfunction

function! s:FindDiffSyntax(hl) abort
  " find an alternate diff syntax hl, '?': not found, '': n/a
  let da = (a:hl =~? 'add') ? ['Added', 'Identifier'] :
            \(a:hl =~? 'delete') ? ['Removed', 'Special'] :
            \(a:hl =~? 'change') ? ['Changed', 'Preproc'] : []
  if !empty(da) && a:hl =~? 'inline\|intraline'
    " inline hl
    let ds = '?'
  elseif !empty(filter(['bg', 'bold', 'italic', 'reverse', 'inverse',
                      \'standout', 'underline', 'undercurl', 'strikethrough'],
                        \'!empty(synIDattr(synIDtrans(hlID(a:hl)), v:val))'))
    " bg/attr-enabled hl
    let ds = '?'
    if !empty(filter(da, '0 < hlID(v:val)')) | let ds = da[0] | endif
  else
    let ds = ''
  endif
  return ds
endfunction

let s:dev = ['ColorScheme', 'OptionSet', 'TextChanged', 'BufDelete']

function! s:SetEvent() abort
  let ac = []
  let bz = filter(range(1, bufnr('$')),
            \'bufloaded(v:val) && type(getbufvar(v:val, s:dus)) == type({})')
  for ev in s:dev
    if ev == 'ColorScheme'
      let ac += [[ev, empty(bz) ? '' : '*']]
    elseif ev == 'OptionSet'
      let ac += [[ev, empty(bz) ? '' : 'diffopt']]
    else
      let ac += [[ev, '']]
      for bn in bz | let ac += [[ev, '<buffer=' . bn . '>']] | endfor
    endif
  endfor
  call execute(map(ac, '"autocmd! " . s:dus . " " . v:val[0] .
                                  \((empty(v:val[1])) ? "" : " " . v:val[1] .
                    \" call s:HandleEvent(" . index(s:dev, v:val[0]) . ")")'))
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
        call win_execute(wn, 'call diffunitsyntax#DiffUnitSyntax()')
      endif
    endif
  endif
endfunction

function! s:gitsigns(bn, lv, ...) abort
  for ti in gettabinfo()
    for wn in ti.windows
      if !empty(getwinvar(wn, 'gitsigns_preview')) &&
                                        \!empty(win_gettype(wn)) && 2 <= a:lv
        call win_execute(wn, 'call diffunitsyntax#DiffUnitSyntax()')
      endif
    endfor
  endfor
endfunction

function! s:neogit(bn, lv, ...) abort
  if bufname(a:bn) =~? '^Neogit'
    let wn = bufwinid(a:bn)
    if wn != -1
      call win_execute(wn, 'call diffunitsyntax#DiffUnitSyntax()')
    endif
  endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" vim: ts=2 sw=0 sts=-1 et
