vim9 noclear

if exists('loaded') | finish | endif
var loaded = true

const ERROR_FILE = tempname()

# Interface {{{1
def unix#sudo#edit(file: string, bang: bool) #{{{2
    var _file = (empty(file) ? expand('%') : file)->fnamemodify(':p')
    unix#sudo#setup(_file)

    if !&modified || !empty(file)
        exe 'e' .. (bang ? '!' : '') .. ' ' .. file
    endif

    if empty(file) || expand('%:p') == fnamemodify(file, ':p')
        set noreadonly
    endif
enddef

def unix#sudo#setup(file: string) #{{{2
    if !filereadable(file) && !exists('#BufReadCmd#' .. fnameescape(file))
        exe 'au BufReadCmd ' .. fnameescape(file) .. ' exe SudoReadCmd()'
    endif
    if !filewritable(file) && !exists('#BufWriteCmd#' .. fnameescape(file))
        exe 'au BufReadPost ' .. fnameescape(file) .. ' set noreadonly'
        exe 'au BufWriteCmd ' .. fnameescape(file) .. ' exe SudoWriteCmd()'
    endif
enddef
#}}}1
# Core {{{1
def SilentSudoCmd(editor: string): list<string> #{{{2
    var cmd = 'env SUDO_EDITOR=' .. editor .. ' VISUAL=' .. editor .. ' sudo -e'
    if !has('gui_running')
        return ['silent', cmd]

    elseif !empty($SUDO_ASKPASS)
        || filereadable('/etc/sudo.conf')
        && readfile('/etc/sudo.conf', 50)->filter((_, v) => v =~ '^Path askpass ')->len()
        return ['silent', cmd .. ' -A']

    else
        return ['', cmd]
    endif
enddef

def SudoEditInit() #{{{2
    let files = split($SUDO_COMMAND, ' ')[1 : -1]
    if len(files) == argc()
        for i in argc()->range()
            exe 'autocmd BufEnter ' .. argv(i)->fnameescape()
                .. 'if empty(&ft) || &ft is "conf"'
                .. '|do filetypedetect BufReadPost ' .. fnameescape(files[i])
                .. '|endif'
        endfor
    endif
enddef

if $SUDO_COMMAND =~ '^sudoedit '
    SudoEditInit()
endif

def SudoError(): string #{{{2
    var error = readfile(ERROR_FILE)->join(' | ')
    if error =~ '^sudo' || v:shell_error
        system('')
        return strlen(error) ? error : 'Error invoking sudo'
    else
        return error
    endif
enddef

def SudoReadCmd(): string #{{{2
    sil keepj :%d _
    var silent: string
    var cmd: string
    [silent, cmd] = SilentSudoCmd('cat')
    sil exe printf('read !%s %%:p:S 2>%s', cmd, ERROR_FILE)
    var exit_status = v:shell_error
    # reset `v:shell_error`
    system('')
    sil keepj :1d _
    setl nomodified
    if exit_status
        return 'echoerr ' .. SudoError()->string()
    endif
    return ''
enddef

def SudoWriteCmd(): string #{{{2
    var silent: string
    var cmd: string
    [silent, cmd] = SilentSudoCmd('tee')
    cmd ..= ' %:p:S >/dev/null'
    cmd ..= ' 2> ' .. ERROR_FILE
    exe silent 'write !' .. cmd
    var error = SudoError()
    if !empty(error)
        return 'echoerr ' .. string(error)
    else
        setl nomodified
        return ''
    endif
enddef

