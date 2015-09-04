path = require 'path'
{Disposable, CompositeDisposable} = require 'event-kit'
ipc = require 'ipc'
shell = require 'shell'
fs = require 'fs-plus'

# Handles low-level events related to the window.
module.exports =
class WindowEventHandler
  constructor: ->
    @reloadRequested = false
    @subscriptions = new CompositeDisposable

    @on(ipc, 'message', @handleIPCMessage)
    @on(ipc, 'command', @handleIPCCommand)
    @on(ipc, 'context-command', @handleIPCContextCommand)

    @addEventListener(window, 'focus', @handleWindowFocus)
    @addEventListener(window, 'blur', @handleWindowBlur)
    @addEventListener(window, 'beforeunload', @handleWindowBeforeunload)
    @addEventListener(window, 'unload', @handleWindowUnload)
    @addEventListener(window, 'window:toggle-full-screen', @handleWindowToggleFullScreen)
    @addEventListener(window, 'window:close', @handleWindowClose)
    @addEventListener(window, 'window:reload', @handleWindowReload)
    @addEventListener(window, 'window:toggle-dev-tools', @handleWindowToggleDevTools)
    @addEventListener(window, 'window:toggle-menu-bar', @handleWindowToggleMenuBar) if process.platform in ['win32', 'linux']

    @addEventListener(document, 'core:focus-next', @handleFocusNext)
    @addEventListener(document, 'core:focus-previous', @handleFocusPrevious)
    @addEventListener(document, 'keydown', @handleDocumentKeydown)
    @addEventListener(document, 'drop', @handleDocumentDrop)
    @addEventListener(document, 'dragover', @handleDocumentDragover)
    @addEventListener(document, 'click', @handleDocumentClick)
    @addEventListener(document, 'submit', @handleDocumentSubmit)
    @addEventListener(document, 'contextmenu', @handleDocumentContextmenu)

    @handleNativeKeybindings()

  # Wire commands that should be handled by Chromium for elements with the
  # `.native-key-bindings` class.
  handleNativeKeybindings: ->
    bindCommandToAction = (command, action) =>
      @addEventListener document, command, (event) ->
        if event.target.webkitMatchesSelector('.native-key-bindings')
          atom.getCurrentWindow().webContents[action]()

    bindCommandToAction('core:copy', 'copy')
    bindCommandToAction('core:paste', 'paste')
    bindCommandToAction('core:undo', 'undo')
    bindCommandToAction('core:redo', 'redo')
    bindCommandToAction('core:select-all', 'selectAll')
    bindCommandToAction('core:cut', 'cut')

  unsubscribe: ->
    @subscriptions.dispose()

  on: (target, eventName, handler) ->
    target.on(eventName, handler)
    @subscriptions.add(new Disposable ->
      target.removeListener(eventName, handler)
    )

  addEventListener: (target, eventName, handler) ->
    target.addEventListener(eventName, handler)
    @subscriptions.add(new Disposable(-> target.removeEventListener(eventName, handler)))

  handleDocumentKeydown: (event) ->
    atom.keymaps.handleKeyboardEvent(event)
    event.stopImmediatePropagation()

  handleDrop: (evenDocumentt) ->
    event.preventDefault()
    event.stopPropagation()

  handleDragover: (Documentevent) ->
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = 'none'

  eachTabIndexedElement: (callback) ->
    for element in document.querySelectorAll('[tabindex]')
      continue if element.disabled
      continue unless element.tabIndex >= 0
      callback(element, element.tabIndex)
    return

  handleFocusNext: =>
    focusedTabIndex = document.activeElement.tabIndex ? -Infinity

    nextElement = null
    nextTabIndex = Infinity
    lowestElement = null
    lowestTabIndex = Infinity
    @eachTabIndexedElement (element, tabIndex) ->
      if tabIndex < lowestTabIndex
        lowestTabIndex = tabIndex
        lowestElement = element

      if focusedTabIndex < tabIndex < nextTabIndex
        nextTabIndex = tabIndex
        nextElement = element

    if nextElement?
      nextElement.focus()
    else if lowestElement?
      lowestElement.focus()

  handleFocusPrevious: =>
    focusedTabIndex = document.activeElement.tabIndex ? Infinity

    previousElement = null
    previousTabIndex = -Infinity
    highestElement = null
    highestTabIndex = -Infinity
    @eachTabIndexedElement (element, tabIndex) ->
      if tabIndex > highestTabIndex
        highestTabIndex = tabIndex
        highestElement = element

      if focusedTabIndex > tabIndex > previousTabIndex
        previousTabIndex = tabIndex
        previousElement = element

    if previousElement?
      previousElement.focus()
    else if highestElement?
      highestElement.focus()

  handleIPCMessage: (message, detail) ->
    switch message
      when 'open-locations'
        needsProjectPaths = atom.project?.getPaths().length is 0

        for {pathToOpen, initialLine, initialColumn} in detail
          if pathToOpen? and needsProjectPaths
            if fs.existsSync(pathToOpen)
              atom.project.addPath(pathToOpen)
            else if fs.existsSync(path.dirname(pathToOpen))
              atom.project.addPath(path.dirname(pathToOpen))
            else
              atom.project.addPath(pathToOpen)

          unless fs.isDirectorySync(pathToOpen)
            atom.workspace?.open(pathToOpen, {initialLine, initialColumn})
        return
      when 'update-available'
        atom.updateAvailable(detail)

  handleIPCCommand: (command, args...) ->
    activeElement = document.activeElement
    # Use the workspace element view if body has focus
    if activeElement is document.body and workspaceElement = atom.views.getView(atom.workspace)
      activeElement = workspaceElement

    atom.commands.dispatch(activeElement, command, args[0])

  handleIPCContextCommand: (command, args...) ->
    atom.commands.dispatch(atom.contextMenu.activeElement, command, args)

  handleWindowFocus: ->
    document.body.classList.remove('is-blurred')

  handleWindowBlur: ->
    document.body.classList.add('is-blurred')
    atom.storeDefaultWindowDimensions()

  handleWindowBeforeunload: =>
    confirmed = atom.workspace?.confirmClose(windowCloseRequested: true)
    atom.hide() if confirmed and not @reloadRequested and atom.getCurrentWindow().isWebViewFocused()
    @reloadRequested = false

    atom.storeDefaultWindowDimensions()
    atom.storeWindowDimensions()
    if confirmed
      atom.unloadEditorWindow()
    else
      ipc.send('cancel-window-close')

    confirmed

  handleWindowUnload: ->
    atom.removeEditorWindow()

  handleWindowToggleFullScreen: ->
    atom.toggleFullScreen()

  handleWindowClose: ->
    atom.close()

  handleWindowReload: ->
    @reloadRequested = true
    atom.reload()

  handleWindowToggleDevTools: ->
    atom.toggleDevTools()

  handleWindowToggleMenuBar: ->
    atom.config.set('core.autoHideMenuBar', not atom.config.get('core.autoHideMenuBar'))

    if atom.config.get('core.autoHideMenuBar')
      detail = "To toggle, press the Alt key or execute the window:toggle-menu-bar command"
      atom.notifications.addInfo('Menu bar hidden', {detail})

  handleDocumentClick: (event) ->
    if (event.target.matches('a'))
      event.preventDefault()
      location = event.target?.getAttribute('href')
      if location and location[0] isnt '#' and /^https?:\/\//.test(location)
        shell.openExternal(location)

  handleDocumentSubmit: (event) ->
    # Prevent form submits from changing the current window's URL
    if event.target.matches('form')
      event.preventDefault()

  handleDocumentContextmenu: (event) ->
    event.preventDefault()
    atom.contextMenu.showForEvent(event)
