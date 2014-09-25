Range = require('xpath-range').Range

Delegator = require('./delegator')
Util = require('./util')

$ = Util.$
_t = Util.TranslationString

ADDER_NS = 'annotator-adder'
TEXTSELECTOR_NS = 'annotator-textselector'

ADDER_HTML =
  """
  <div class="annotator-adder annotator-hide">
    <button type="button">#{_t('Annotate')}</button>
  </div>
  """


# highlightRange wraps the DOM Nodes within the provided range with a highlight
# element of the specified class and returns the highlight Elements.
#
# normedRange - A NormalizedRange to be highlighted.
# cssClass - A CSS class to use for the highlight (default: 'annotator-hl')
#
# Returns an array of highlight Elements.
highlightRange = (normedRange, cssClass = 'annotator-hl') ->
  white = /^\s*$/

  hl = $("<span class='#{cssClass}'></span>")

  # Ignore text nodes that contain only whitespace characters. This prevents
  # spans being injected between elements that can only contain a restricted
  # subset of nodes such as table rows and lists. This does mean that there
  # may be the odd abandoned whitespace node in a paragraph that is skipped
  # but better than breaking table layouts.
  for node in normedRange.textNodes() when not white.test(node.nodeValue)
    $(node).wrapAll(hl).parent().show()[0]


# Public: Base class for the Editor and Viewer elements. Contains methods that
# are shared between the two.
class Widget extends Delegator

  # Classes used to alter the widgets state.
  classes:
    hide: 'annotator-hide'
    invert:
      x: 'annotator-invert-x'
      y: 'annotator-invert-y'

  template: """<div></div>"""

  # Default options for the plugin.
  options:
    # A CSS selector or Element to append the Widget to.
    appendTo: 'body'

  # Public: Creates a new Widget instance.
  #
  # Returns a new Widget instance.
  constructor: (options) ->
    super $(@template)[0], options
    @classes = $.extend {}, Widget.prototype.classes, @classes
    @options = $.extend {}, Widget.prototype.options, @options

  # Public: Destroy the Widget, unbinding all events and removing the element.
  #
  # Returns nothing.
  destroy: ->
    super
    @element.remove()

  # Public: Renders the widget
  render: ->
    @element.appendTo(@options.appendTo)

  # Public: Show the widget.
  #
  # Returns nothing.
  show: ->
    @element.removeClass(@classes.hide)

    # invert if necessary
    this.checkOrientation()

  # Public: Hide the widget.
  #
  # Returns nothing.
  hide: ->
    $(@element).addClass(@classes.hide)

  # Public: Returns true if the widget is currently displayed, false otherwise.
  #
  # Examples
  #
  #   widget.show()
  #   widget.isShown() # => true
  #
  #   widget.hide()
  #   widget.isShown() # => false
  #
  # Returns true if the widget is visible.
  isShown: ->
    not $(@element).hasClass(@classes.hide)

  checkOrientation: ->
    this.resetOrientation()

    window   = $(Util.getGlobal())
    widget   = @element.children(":first")
    offset   = widget.offset()
    viewport = {
      top: window.scrollTop(),
      right: window.width() + window.scrollLeft()
    }
    current = {
      top: offset.top
      right: offset.left + widget.width()
    }

    if (current.top - viewport.top) < 0
      this.invertY()

    if (current.right - viewport.right) > 0
      this.invertX()

    this

  # Public: Resets orientation of widget on the X & Y axis.
  #
  # Examples
  #
  #   widget.resetOrientation() # Widget is original way up.
  #
  # Returns itself for chaining.
  resetOrientation: ->
    @element.removeClass(@classes.invert.x).removeClass(@classes.invert.y)
    this

  # Public: Inverts the widget on the X axis.
  #
  # Examples
  #
  #   widget.invertX() # Widget is now right aligned.
  #
  # Returns itself for chaining.
  invertX: ->
    @element.addClass(@classes.invert.x)
    this

  # Public: Inverts the widget on the Y axis.
  #
  # Examples
  #
  #   widget.invertY() # Widget is now upside down.
  #
  # Returns itself for chaining.
  invertY: ->
    @element.addClass(@classes.invert.y)
    this

  # Public: Find out whether or not the widget is currently upside down
  #
  # Returns a boolean: true if the widget is upside down
  isInvertedY: ->
    @element.hasClass(@classes.invert.y)

  # Public: Find out whether or not the widget is currently right aligned
  #
  # Returns a boolean: true if the widget is right aligned
  isInvertedX: ->
    @element.hasClass(@classes.invert.x)


# Adder shows and hides an annotation adder button that can be clicked on to
# create an annotation.
class Adder extends Widget
  events:
    "button click": "_onClick"
    "button mousedown": "_onMousedown"

  template: ADDER_HTML

  constructor: (registry, options) ->
    super options
    @registry = registry
    @ignoreMouseup = false

    @interactionPoint = null
    @selectedRanges = null

    @document = @element[0].ownerDocument
    $(@document.body).on("mouseup.#{ADDER_NS}", this._onMouseup)
    this.render()

  destroy: ->
    super
    $(@document.body).off(".#{ADDER_NS}")

  onSelection: (ranges, event) =>
    if ranges?.length > 0
      @selectedRanges = ranges
      @interactionPoint = Util.mousePosition(event)
      this.show()
    else
      @selectedRanges = []
      @interactionPoint = null
      this.hide()

  # Public: Show the adder.
  #
  # Returns nothing.
  show: =>
    if @interactionPoint?
      @element.css({
        top: @interactionPoint.top,
        left: @interactionPoint.left
      })
    super

  # Event callback: called when the mouse button is depressed on the adder.
  #
  # event - A mousedown Event object
  #
  # Returns nothing.
  _onMousedown: (event) ->
    # Do nothing for right-clicks, middle-clicks, etc.
    if event.which != 1
      return

    event?.preventDefault()
    # Prevent the selection code from firing when the mouse button is released
    @ignoreMouseup = true

  # Event callback: called when the mouse button is released
  #
  # event - A mouseup Event object
  #
  # Returns nothing.
  _onMouseup: (event) ->
    # Do nothing for right-clicks, middle-clicks, etc.
    if event.which != 1
      return

    # Prevent the selection code from firing when the ignoreMouseup flag is set
    if @ignoreMouseup
      event.stopImmediatePropagation()


  # Event callback: called when the adder is clicked. The click event is used as
  # well as the mousedown so that we get the :active state on the adder when
  # clicked.
  #
  # event - A mousedown Event object
  #
  # Returns nothing.
  _onClick: (event) ->
    # Do nothing for right-clicks, middle-clicks, etc.
    if event.which != 1
      return

    event?.preventDefault()

    # Hide the adder
    this.hide()
    @ignoreMouseup = false

    # Create a new annotation
    @registry.annotations.create({
      ranges: @selectedRanges
    })


# Highlighter provides a simple way to draw highlighted <span> tags over
# annotated ranges within a document.
class Highlighter
  options:
    # The CSS class to apply to drawn highlights
    highlightClass: 'annotator-hl'
    # Number of annotations to draw at once
    chunkSize: 10
    # Time (in ms) to pause between drawing chunks of annotations
    chunkDelay: 10

  # Public: Create a new instance of the Highlighter
  #
  # element - The root Element on which to dereference annotation ranges and
  #           draw highlights.
  # options - An options Object containing configuration options for the plugin.
  #           See `Highlights.options` for available options.
  #
  # Returns a new plugin instance.
  constructor: (@element, options) ->
    @options = $.extend(true, {}, @options, options)


  destroy: ->
    $(@element).find(".#{@options.highlightClass}").each (i, el) ->
      $(el).contents().insertBefore(el)
      $(el).remove()

  # Public: Draw highlights for all the given annotations
  #
  # annotations - An Array of annotation Objects for which to draw highlights.
  #
  # Returns nothing.
  drawAll: (annotations) =>
    return new Promise((resolve, reject) =>
      highlights = []

      loader = (annList = []) =>
        now = annList.splice(0, @options.chunkSize)

        for a in now
          highlights = highlights.concat(this.draw(a))

        # If there are more to do, do them after a delay
        if annList.length > 0
          setTimeout((-> loader(annList)), @options.chunkDelay)
        else
          resolve(highlights)

      clone = annotations.slice()
      loader(clone)
    )

  # Public: Draw highlights for the annotation.
  #
  # annotation - An annotation Object for which to draw highlights.
  #
  # Returns an Array of drawn highlight elements.
  draw: (annotation) =>
    normedRanges = []
    for r in annotation.ranges
      try
        normedRanges.push(Range.sniff(r).normalize(@element))
      catch e
        if e not instanceof Range.RangeError
          # Oh Javascript, why you so crap? This will lose the traceback.
          throw e
        # Otherwise, we simply swallow the error. Callers are responsible for
        # only trying to draw valid annotations.

    annotation._local ?= {}
    annotation._local.highlights ?= []

    for normed in normedRanges
      $.merge(
        annotation._local.highlights,
        highlightRange(normed, @options.highlightClass)
      )

    # Save the annotation data on each highlighter element.
    $(annotation._local.highlights).data('annotation', annotation)
    # Add a data attribute for annotation id if the annotation has one
    if annotation.id?
      $(annotation._local.highlights).attr('data-annotation-id', annotation.id)

    return annotation._local.highlights

  # Public: Remove the drawn highlights for the given annotation.
  #
  # annotation - An annotation Object for which to purge highlights.
  #
  # Returns nothing.
  undraw: (annotation) ->
    if annotation._local?.highlights?
      for h in annotation._local.highlights when h.parentNode?
        $(h).replaceWith(h.childNodes)
      delete annotation._local.highlights

  # Public: Redraw the highlights for the given annotation.
  #
  # annotation - An annotation Object for which to redraw highlights.
  #
  # Returns nothing.
  redraw: (annotation) =>
    this.undraw(annotation)
    this.draw(annotation)


# TextSelector monitors a document (or a specific element) for text selections
# and can notify another object of a selection event
class TextSelector

  constructor: (element, options) ->
    @element = element
    @options = options

    if @element.ownerDocument?
      @document = @element.ownerDocument
      $(@document.body)
      .on("mouseup.#{TEXTSELECTOR_NS}", this._checkForEndSelection)
    else
      console.warn("You created an instance of the TextSelector on an element
                    that doesn't have an ownerDocument. This won't work! Please
                    ensure the element is added to the DOM before the plugin is
                    configured:", @element)

  destroy: ->
    $(@document.body).off(".#{TEXTSELECTOR_NS}")

  # Public: capture the current selection from the document, excluding any nodes
  # that fall outside of the adder's `element`.
  #
  # Returns an Array of NormalizedRange instances.
  captureDocumentSelection: ->
    selection = Util.getGlobal().getSelection()

    ranges = []
    rangesToIgnore = []
    unless selection.isCollapsed
      ranges = for i in [0...selection.rangeCount]
        r = selection.getRangeAt(i)
        browserRange = new Range.BrowserRange(r)
        normedRange = browserRange.normalize().limit(@element)

        # If the new range falls fully outside our @element, we should add it
        # back to the document but not return it from this method.
        rangesToIgnore.push(r) if normedRange is null

        normedRange

      # BrowserRange#normalize() modifies the DOM structure and deselects the
      # underlying text as a result. So here we remove the selected ranges and
      # reapply the new ones.
      selection.removeAllRanges()

    for r in rangesToIgnore
      selection.addRange(r)

    # Remove any ranges that fell outside @element.
    ranges = $.grep(ranges, (range) ->
      # Add the normed range back to the selection if it exists.
      if range
        drange = @document.createRange()
        drange.setStartBefore(range.start)
        drange.setEndAfter(range.end)
        selection.addRange(drange)
      range
    )

    return ranges

  # Event callback: called when the mouse button is released. Checks to see if a
  # selection has been made and if so displays the adder.
  #
  # event - A mouseup Event object.
  #
  # Returns nothing.
  _checkForEndSelection: (event) =>
    _nullSelection = =>
      if typeof @options.onSelection == 'function'
        @options.onSelection([], event)

    # Get the currently selected ranges.
    selectedRanges = this.captureDocumentSelection()

    if selectedRanges.length == 0
      _nullSelection()
      return

    # Don't show the adder if the selection was of a part of Annotator itself.
    for range in selectedRanges
      container = range.commonAncestor
      if $(container).hasClass('annotator-hl')
        container = $(container).parents('[class!=annotator-hl]')[0]
      if this._isAnnotator(container)
        _nullSelection()
        return

    if typeof @options.onSelection == 'function'
      @options.onSelection(selectedRanges, event)


  # Determines if the provided element is part of Annotator. Useful for ignoring
  # mouse actions on the annotator elements.
  #
  # element - An Element or TextNode to check.
  #
  # Returns true if the element is a child of an annotator element.
  _isAnnotator: (element) ->
    !!$(element)
      .parents()
      .addBack()
      .filter('[class^=annotator-]')
      .length


exports.Adder = Adder
exports.Highlighter = Highlighter
exports.TextSelector = TextSelector
exports.Widget = Widget
