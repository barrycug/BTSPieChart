# BTSPieChart

### Created by Brian Coyner

This is a simple Pie Chart view built using Core Animation. The purpose of this app is to demonstrate a technique for animating arc (i.e. wedges) of a pie chart. 

The pie chart contains the following features:

- add new slices (animated)
- remove selected slice (animated)
- update existing pie values (animated)
- interactive slice selection 

__NOTE:__ this is NOT a complete "Pie Chart" implementation. The purpose is to demonstrate a technique for building and animating wedges in a pie cart layout. See the _How Does It Work?_ section below. 

The view uses a data source (number of slices, slice value) and delegate (selection tracking)

### How does it work?:

- Animating the start and end points does not animate correctly
  - Specifically, Core Animation animates between two arcs (wedges) in a manner that makes the pie chart looks "weird" while animating
- A standard `NSTimer` is added to the main thread's run loop (fires every 1/60th sec) while the animation takes place
  - the timer is invalidated once the animations complete
- Each slice/ pie layer contains two `CABasicAnimation` objects
  - each animation object stores two custom properties ("start angle", "end angle")
- There is one timer per N number of slices
- The `CABasicAnimation` objects still provide interpolation (fromValue, toValue)
- During a timer event, the current interpolated values are pulled from each layer's animation ("start angle", "end angle")  and a new `CGPathRef` is created to represent the new "wedge".
- The new `CGPathRef` is set on the pie layer, which is a standard `CAShapeLayer`

### Highlights

- See section "Animation Delegate + Run Loop Timer"
- See `BTSArcLayerAddAnimationDelegate` (private class at end of file)
- See `BTSArcLayerDefaultAnimationDelegate` (private class at end of file)

### Notes

- I find this solution to be easy to understand and implement.
- this same technique can be applied to other types of paths

### Why the use of `NSTimer`?

- Core Animation animates between two arcs (wedges) in a manner that makes the pie chart looks "weird" while animating.
- The timer gives a hook to capture the layer's interpolated presentation layer values and re-generate a CGPathRef for each `CAShapeLayer`.
 
###  Known issues

Known issues in this version that need to be addressed in a future release

- Deleting more than one slice at a time (i.e. deleting a second slice while the first slice is still animating) causes strange results
  - the `BTSDemoViewController` enforces that only one slice can be removed at at time (i.e. you cannot hit the "-" button really fast). You can, however, hit the "+" really fast. 
- If there is only one slice, the selection border shows a line from the center to the edge of the arc
- There is a graphics edge case that allows the view's background color to bleed through the edges of two adjacent `CAShapeLayer` slices
- Each `CAShapeLayer` shows the current value as a `CATextLayer` sublayer. When there are lots of slices, the text layers may be hidden
   by other slice layers. One way to fix this is to add each `CATextLayer` to a separate `CALayer` that fits directly over the top of the main layer. 