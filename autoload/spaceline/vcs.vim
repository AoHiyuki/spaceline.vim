" =============================================================================
" Filename: spaceline.vim
" Author: taigacute
" URL: https://github.com/taigacute/spaceline.vim
" License: MIT License
" =============================================================================

let s:diff_nerdfonts_icon = exists('g:spaceline_custom_diff_icon') ? get(g:,'spaceline_custom_diff_icon'): ['','','']
let s:git_diff_cmd = add(has('win32') ? ['cmd', '/c'] : ['bash', '-c'], 'git diff --stat --word-diff=porcelain --no-color --no-ext-diff -U0 -- ')
let s:spaceline_diff_status = []

" reference https://github.com/itchyny/vim-gitbranch/blob/master/plugin/gitbranch.vim
function! spaceline#vcs#git_branch() abort
  let git_branch_icon = exists('g:spaceline_git_branch_icon') ? get(g:,'spaceline_git_branch_icon') : ''
  if get(b:, 'gitbranch_pwd', '') !=# expand('%:p:h') || !has_key(b:, 'gitbranch_path')
    call spaceline#vcs#gitbranch_detect(expand('%:p:h'))
  endif
  if has_key(b:, 'gitbranch_path') && filereadable(b:gitbranch_path)
    let branch = get(readfile(b:gitbranch_path), 0, '')
    if branch =~# '^ref: '
      return git_branch_icon .' '. substitute(branch, '^ref: \%(refs/\%(heads/\|remotes/\|tags/\)\=\)\=', '', '')
    elseif branch =~# '^\x\{20\}'
      return git_branch_icon .' '. branch[:6]
    endif
  endif
  return ''
endfunction

function! s:gitbranch_dir(path) abort
  let path = a:path
  let prev = ''
  while path !=# prev
    let dir = path . '/.git'
    let type = getftype(dir)
    if type ==# 'dir' && isdirectory(dir.'/objects') && isdirectory(dir.'/refs') && getfsize(dir.'/HEAD') > 10
      return dir
    elseif type ==# 'file'
      let reldir = get(readfile(dir), 0, '')
      if reldir =~# '^gitdir: '
        return simplify(path . '/' . reldir[8:])
      endif
    endif
    let prev = path
    let path = fnamemodify(path, ':h')
  endwhile
  return ''
endfunction

function! spaceline#vcs#gitbranch_detect(path) abort
  unlet! b:gitbranch_path
  let b:gitbranch_pwd = expand('%:p:h')
  let dir = s:gitbranch_dir(a:path)
  if dir !=# ''
    let path = dir . '/HEAD'
    if filereadable(path)
      let b:gitbranch_path = path
    endif
  endif
  call s:query_git()
  echo s:spaceline_diff_status
endfunction

function! s:add_diff_icon(type) abort
  let diff_nerdfonts_icon = exists('g:spaceline_custom_diff_icon') ? get(g:,'spaceline_custom_diff_icon'): ['','','']
  let difficon = get(diff_nerdfonts_icon,a:type,'')
  let diffdata = split(get(b:, 'coc_git_status', ''),' ')
  let diff_flags = ''
  if a:type == 0
    let diff_flags = '+'
  elseif a:type == 1
    let diff_flags = '-'
  elseif a:type == 2
    let diff_flags = '\~'
  endif
  for item in diffdata
    if matchend(item,diff_flags) > 0
        if g:symbol == 1
          return item
        else
          return substitute(item, diff_flags, difficon, '').' '
        endif
    endif
  endfor
endfunction

function! spaceline#vcs#diff_add() abort
  return s:add_diff_icon(0)
endfunction

function! spaceline#vcs#diff_remove() abort
  return s:add_diff_icon(1)
endfunction

function! spaceline#vcs#diff_modified() abort
  return s:add_diff_icon(2)
endfunction

function! s:query_git()
  let l:filename = expand('%:f')
  let l:cmd = add(s:git_diff_cmd , l:filename)
  if l:filename !=# ''
    if has('nvim')
      let l:callbacks = {
      \   'on_stdout': function('s:JobHandler'),
      \   'on_stderr': function('s:JobHandler'),
      \   'on_exit': function('s:JobHandler')
      \ }
      let l:job_id = jobstart(l:cmd, extend({'stdout': [], 'stderr': []},l:callbacks))
    endif
  endif
endfunction

function! s:modified_count(stdout)
  let l:modified = 0
  let l:plus = 0
  let l:minus = 0
  let l:blank = 0
  let l:counting = 0  " true/false (are we supposed to count the current line?)

  for l:output_line in a:stdout
    let l:firstchar = l:output_line[0]

    " start counting after the first '@' mark
    if l:firstchar ==# '@' && l:counting ==# 0
      let l:counting = 1
    elseif l:firstchar ==# '+' && l:counting ==# 1
      let l:plus = l:plus + 1
    elseif l:firstchar ==# '-' && l:counting ==# 1
      let l:minus = l:minus + 1
    elseif l:firstchar ==# ' ' && l:counting ==# 1
      let l:blank = l:blank + 1
    " determine if a line was added/deleted/modified at the end of a line
    elseif l:firstchar ==# '~' && l:counting ==# 1
      if l:blank !=# 0
        let l:modified = l:modified + 1
      elseif l:plus !=# 0 && l:minus !=# 0
        let l:modified = l:modified + 1
      endif

      " reset counters at the end of each line
      let l:plus = 0
      let l:minus = 0
      let l:blank = 0
    endif
  endfor

  return l:modified
endfunction

function! s:str2nr(str)
  return empty(str2nr(a:str)) ? 0 : str2nr(a:str)
endfunction

function! s:JobHandler(job_id,data,event) dict
  if a:event == 'stdout'
    let self.stdout = self.stdout + a:data
  elseif a:event == 'stderr'
    let self.stderr = self.stderr + a:data
  endif

  let l:modified = s:modified_count(self.stdout)
  let l:change_summary = self.stdout[1]
  let l:regex = '\v[^,]+, ((\d+) [a-z]+\(\+\)[, ]*)?((\d+) [a-z]+\(-\))?'
  let l:matched =  matchlist(l:change_summary, l:regex)
  let l:insertions = s:str2nr(l:matched[2])
  let l:deletions = s:str2nr(l:matched[4])
  let l:added = l:insertions - l:modified
  let l:deleted = l:deletions - l:modified

  if l:added <# 0 || l:deleted <# 0
    let l:negativity = min([l:added, l:deleted])
    let l:added = l:added - l:negativity
    let l:deleted = l:deleted - l:negativity
    let l:modified = l:modified + l:negativity
  endif

  let s:spaceline_diff_status=[s:diff_nerdfonts_icon[0].l:added,s:diff_nerdfonts_icon[1].l:deleted,s:diff_nerdfonts_icon[2].l:modified]
endfunction
