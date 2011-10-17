//
//  BTSPieView.m
//  TouchPie
//
//  Created by Brian Coyner on 9/9/11.
//  Copyright (c) 2011 Brian Coyner. All rights reserved.
//

#import "BTSPieView.h"
#import <QuartzCore/QuartzCore.h>

//
// This is a simple Pie Chart view built using Core Animation layers.
//
// The pie chart contains the following features:
// - add new slices (animated)
// - remove selected slice (animated)
// - update existing pie values (animated)
//
// NOTE: this is NOT a complete Pie Chart View implementation. The purpose is to demonstrate a technique for building and animating 
//       slices/wedges in a pie cart layout. See the How Does It Work? section below. 
//
// The view uses a data source (number of slices, slice value) and delegate (selection tracking)
// 
// Known issues in this version that need to be addressed in a future release
// - Deleting more than one slice at a time (i.e. deleting a second slice while the first slice is still animating) causes strange results
// - If there is only one slice, the selection border shows a line from the center to the edge of the arc
// - There is a graphics edge case that allows the view's background color to bleed through the edges of two adjacent CAShapeLayer slices
// - Each CAShapeLayer shows the current value as a CATextLayer sublayer. When there are lots of slices, the text layers may be hidden
//   by other slice layers. One way to fix this is to add each CATextLayer to a separate CALayer that fits directly over the top of the main layer. 
// 
// How does it work?
// - A simple NSTimer is added to the main thread's run loop (fires every 1/60th sec) while the animation takes place
//   - the timer is invalidated once the animations complete
// - Each slice/ pie layer contains two CABasicAnimation objects
//   - each animation object stores two custom properties ("start angle", "end angle")
// - There is one timer per N number of slices
// - The CABasicAnimation objects still provide interpolation (fromValue, toValue)
// - During a timer event, the current interpolated values are pulled from each layer's animation ("start angle", "end angle")
//   and a new CGPathRef is created to represent the new "wedge".
// - The new CGPathRef is set on the pie layer, which is a standard CAShapeLayer
//
// Why the use of NSTimer?
// - Core Animation animates between two arcs (wedges) in a manner that makes the pie chart looks "weird" while animating. 
// - The timer gives a hook to capture the layer's interpolated presentation layer values and re-generate a CGPathRef. 
//
// Important Points
// - See section "Animation Delegate + Run Loop Timer"
// - See BTSArcLayerAddAnimationDelegate (private class at end of file)
// - See BTSArcLayerDefaultAnimationDelegate (private class at end of file)
//
// NOTE:
// - obviously there may be other ways to solve this problem. I find this solution to be easy to understand and implement.
// - this same technique can be applied to other types of paths (e.g. sin waves)

NSString * const kBTSArcLayerStartAngle = @"startAngle";
NSString * const kBTSArcLayerEndAngle = @"endAngle";

// Used as a CAAnimationDelegate when animating existing slices
@interface BTSArcLayerDefaultAnimationDelegate : NSObject 
@property (nonatomic, assign) BTSPieView *pieView;
@end

// Used as a CAAnimationDelegate when animating new slices
@interface BTSArcLayerAddAnimationDelegate : NSObject 
@property (nonatomic, assign) BTSPieView *pieView;
@end 

@interface BTSPieView() {
    
    NSInteger _selectedSliceIndex;
    
    NSTimer *_animationTimer;
    NSMutableArray *_animations;
    
    BTSArcLayerDefaultAnimationDelegate *_defaultAnimationDelegate;
    BTSArcLayerAddAnimationDelegate *_addAnimationDelegate;
    
    CGPoint _center;
    CGFloat _radius;
    
    UILabel *_labelForStringSizing;
}

// animation timer used to recalc the pie slices
- (void)updateTimerFired:(NSTimer *)timer;

// layer creation/ manipulation
- (CAShapeLayer *)createPieLayerWithColor:(UIColor *)color;
- (CGSize)sizeThatFitsString:(NSString *)string;
- (void)updateLabelForLayer:(CAShapeLayer *)pieLayer value:(CGFloat)value;

// selection
- (void)maybeNotifyDelegateOfSelectionChangeFrom:(NSUInteger)previousSelection to:(NSUInteger)newSelection;

@end

@implementation BTSPieView

static NSUInteger kDefaultSliceZOrder = 100;

@synthesize dataSource = _dataSource;
@synthesize delegate = _delegate;
@synthesize animationSpeed = _animationSpeed;
@synthesize sliceColors = _sliceColors;

// Helper method to create an arc path for a layer
static CGPathRef CGPathCreateArc(CGPoint center, CGFloat radius, CGFloat startAngle, CGFloat endAngle) 
{
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, center.x, center.y);
    
    // There is no need to perform this "add line"... a line is automatically added by Core Graphics.
    //CGPathAddLineToPoint(path, NULL, center.x + (radius * cos(startAngle)), center.y + (radius * sin(startAngle)));
    CGPathAddArc(path, NULL, center.x, center.y, radius, startAngle, endAngle, 0);
    CGPathCloseSubpath(path);
    
    return path;
}

// TODO: add the ability to programatically create the view.
- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        _selectedSliceIndex = -1;
        _animations = [[NSMutableArray alloc] init];
        
        _addAnimationDelegate = [[BTSArcLayerAddAnimationDelegate alloc] init];
        [_addAnimationDelegate setPieView:self];
    
        _defaultAnimationDelegate = [[BTSArcLayerDefaultAnimationDelegate alloc] init];        
        [_defaultAnimationDelegate setPieView:self];
        
        // Calculate the center and radius based on the parent layer's bounds. This version
        // of the BTSPieView assumes the view does not change size.
        CGRect parentLayerBounds = [[self layer] bounds];
        CGFloat centerX = parentLayerBounds.size.width / 2;
        CGFloat centerY = parentLayerBounds.size.height / 2;
        _center = CGPointMake(centerX, centerY);
        
        // Reduce the radius just a bit so the the pie chart layers do not hug the edge of the view.
        // TODO: this could/ should be a parameterized value.
        _radius = MIN(centerX, centerY) - 10; 
    }
    
    return self;
}

// When invoked executes the data source callback methods to retrieve the number of slices and slice values.
// All operations in this method are animated (add, remove, update).
- (void)reloadData
{
    if (_dataSource) {
        
        [CATransaction begin];
        [CATransaction setAnimationDuration:_animationSpeed];
        
        CALayer *parentLayer = [self layer];
        NSArray *pieLayers = [parentLayer sublayers];
        
        // Do not allow the user to interact with with view while reloading data--includes animating.
        // User interaction is re-enabled in the transaction's completion handler.
        //
        // With a little more work we could let the use interact while the animations are occuring. 
        [self setUserInteractionEnabled:NO];
        
        // NOTE: the completion block MUST be set before any animations are added to a layer
        __block NSMutableArray *layersToRemove = nil;
        [CATransaction setCompletionBlock:^{
            
            [layersToRemove enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                [obj removeFromSuperlayer];
            }];
            
            [layersToRemove removeAllObjects];
            
            // all animations have completed... we can now let the user interfact with the view.
            [self setUserInteractionEnabled:YES];
        }];
        
        // STEP 1: ask our delegate for the new slice count... we will determine if there are new slices or removed slices a little bit later.
        NSUInteger sliceCount = [_dataSource numberOfSlicesInPieView:self];
        
        // STEP 2: calculate the sum of all slices by asking the data source for all slice values
        double sum = 0.0;
        double values[sliceCount];
        for (int index = 0; index < sliceCount; index++) {
            values[index] = [_dataSource pieView:self valueForSliceAtIndex:index];
            sum += values[index];
        }
        
        // STEP 3: calculate the angle for each slice
        double angles[sliceCount];
        for (int index = 0; index < sliceCount; index++) {
            double div = values[index] / sum; 
            div = M_PI * 2 * div;
            
            angles[index] = div;
        }
        
        // For simplicity, the start angle is always zero... no reason it can't be any valid angle in radians.
        CGFloat startAngle = 0.0;
        CGFloat endAngle = startAngle;
        
        //
        // TODO: break this block of code into separate methods (add, remove, update)
        //
        if (sliceCount > [pieLayers count]) {
            
            // TODO - refactor into a separate method
            // ADDING
            
            for (int index = 0; index < sliceCount; index++) {
                
                endAngle += angles[index];
                
                CAShapeLayer *pieLayer;
                
                if (index + 1 < sliceCount) {
                    
                    // A layer already exists at this index
                    // - grab it from the array of sublayers
                    // - change the layer's delegate to the "default", which creates a CABasicAnimation suitable for animating an existing layer 
                    pieLayer = (CAShapeLayer *)[pieLayers objectAtIndex:index];
                    [pieLayer setDelegate:_defaultAnimationDelegate];
                    
                } else {
                    
                    // A new layer is added
                    // - grab the color of the layer (cycle if necessary)
                    // - call the helper method to create the new shape layer with the given color and label
                    UIColor *color = [_sliceColors objectAtIndex:index % [_sliceColors count]];
                    pieLayer = [self createPieLayerWithColor:color];
                    
                    // add the new layer to the parent
                    [parentLayer addSublayer:pieLayer];
                }
                
                [self updateLabelForLayer:pieLayer value:values[index]];
                
                // Shape Layer Animation Technique
                // - our animating pie chart uses two custom layer properties to hold the start and end angles
                [pieLayer setValue:[NSNumber numberWithDouble:endAngle] forKey:kBTSArcLayerEndAngle];
                [pieLayer setValue:[NSNumber numberWithDouble:startAngle] forKey:kBTSArcLayerStartAngle];
                
                startAngle = endAngle;
            }

        } else if (sliceCount == [pieLayers count]) { 
            
            // TODO - refactor into a separate method
            // UPDATING 
            
            // We are updating existing layer values (viz. not adding, or removing). We simply iterate each slice layer and 
            // adjust the start and end angles.
            for (int index = 0; index < sliceCount; index++) {

                CAShapeLayer *pieLayer = (CAShapeLayer *)[pieLayers objectAtIndex:index];
                [pieLayer setDelegate:_defaultAnimationDelegate];
                
                endAngle += angles[index];
                [pieLayer setValue:[NSNumber numberWithDouble:startAngle] forKey:kBTSArcLayerStartAngle];
                [pieLayer setValue:[NSNumber numberWithDouble:endAngle] forKey:kBTSArcLayerEndAngle];                

                [self updateLabelForLayer:pieLayer value:values[index]];
                
                startAngle = endAngle;
            }
            
        } else {
            
            // TODO - refactor into a separate method
            // REMOVING

            // We are removing a layer (this view assumes the removed layer is the one at the "selectedSliceIndex").
            NSInteger indexToRemove = _selectedSliceIndex < 0 ? [pieLayers count] - 1 : _selectedSliceIndex;
            
            CAShapeLayer *pieLayer = [pieLayers objectAtIndex:indexToRemove];
            
            // The removed layer does not animate. Instead we move the removed layer to the "back" and 
            // animate the adjacent layers over the removed layer. This gives the effect that the removed layer is animating.
            // After the animations complete, this layer is removed from the layer hierarchy.
            [pieLayer setDelegate:nil];
            [pieLayer setZPosition:0];

            // IMPORTANT NOTE:
            // - the "layersToRemove" is declared as a __block scoped variable near the top of this method. We are simply 
            //   caching the layer to remove. The layer is removed in a Core Animation completion block (viz. we remove 
            //   the layer only after the other layers are completely covered the removed layer. 
            layersToRemove = [[NSMutableArray alloc] initWithObjects:pieLayer, nil];
            
            if (sliceCount == 0) {
                // the last slice is simply faded away
                [pieLayer setOpacity:0.0];
            } else {
                
                // update the start and end angles for the remaining slices
                for (int index = 0; index < sliceCount; index++) {
                    
                    NSInteger layerIndex = index < indexToRemove ? index : index + 1;
                    CAShapeLayer *pieLayer = (CAShapeLayer *)[pieLayers objectAtIndex:layerIndex];
                    [pieLayer setDelegate:_defaultAnimationDelegate];
                    
                    endAngle += angles[index];
                    [pieLayer setValue:[NSNumber numberWithDouble:endAngle] forKey:kBTSArcLayerEndAngle];                
                    [pieLayer setValue:[NSNumber numberWithDouble:startAngle] forKey:kBTSArcLayerStartAngle];
                    
                    // Update the slice label with the new model value
                    [self updateLabelForLayer:pieLayer value:values[index]];
                    
                    startAngle = endAngle;
                }
            }            
            
            // notify the delegate that the selection is cleared.
            [self maybeNotifyDelegateOfSelectionChangeFrom:_selectedSliceIndex to:-1];
        }      
        
        [CATransaction commit];
    }
}


#pragma mark - Animation Delegate + Run Loop Timer

- (void)updateTimerFired:(NSTimer *)timer;
{   
    CALayer *parentLayer = [self layer];
    NSArray *pieLayers = [parentLayer sublayers];
    
    [pieLayers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {

        NSNumber *presentationLayerStartAngle = [[obj presentationLayer] valueForKey:kBTSArcLayerStartAngle];
        CGFloat interpolatedStartAngle = [presentationLayerStartAngle doubleValue];
        
        NSNumber *presentationLayerEndAngle = [[obj presentationLayer] valueForKey:kBTSArcLayerEndAngle];
        CGFloat interpolatedEndAngle = [presentationLayerEndAngle doubleValue];
        
        // Create a new path based on the current interpolated values and set the path on the CAShapeLayer.
        // This is surprising fast! 
        CGPathRef path = CGPathCreateArc(_center, _radius, interpolatedStartAngle, interpolatedEndAngle);
        [obj setPath:path];
        CFRelease(path);
        
        {
            // CA is already calculating the interpolated angles for each "pie layer"... we can quickly
            // calculate the new text layer position without another animation calculating interpolated values.
            CALayer *labelLayer = [[obj sublayers] objectAtIndex:0];
            CGFloat interpolatedMidAngle = (interpolatedEndAngle + interpolatedStartAngle) / 2;
            CGFloat halfRadius = _radius / 2;
            
            // We do not want an implicit transaction... just move to the new position
            [CATransaction setDisableActions:YES];
            [labelLayer setPosition:CGPointMake(_center.x + (halfRadius * cos(interpolatedMidAngle)), _center.y + (halfRadius * sin(interpolatedMidAngle)))];
            [CATransaction setDisableActions:NO];
        }
    }];
}

- (void)animationDidStart:(CAAnimation *)anim
{
    if (_animationTimer == nil) {
        static float timeInterval = 1.0/60.0;
        _animationTimer= [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(updateTimerFired:) userInfo:nil repeats:YES];
    }
    
    [_animations addObject:anim];
}

- (void)animationDidStop:(CAAnimation *)anim finished:(BOOL)animationCompleted
{
    [_animations removeObject:anim];
    
    if ([_animations count] == 0) {
        [_animationTimer invalidate];
        _animationTimer = nil;
    }
}

#pragma mark - Touch Handing (Selection Notification)

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self touchesMoved:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
    UITouch *touch = [touches anyObject];
    CGPoint point = [touch locationInView:self];
    
    __block NSUInteger selectedIndex = -1;
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    CALayer *parentLayer = [self layer];
    NSArray *pieLayers = [parentLayer sublayers];
    
    [pieLayers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CAShapeLayer *pieLayer = (CAShapeLayer *)obj;
        CGPathRef path = [pieLayer path];
        
        if (CGPathContainsPoint(path, &transform, point, 0)) {
            [pieLayer setLineWidth:2.0];
            [pieLayer setStrokeColor:[UIColor whiteColor].CGColor];
                                       
            [pieLayer setZPosition:MAXFLOAT];
            selectedIndex = idx;
        } else {
            [pieLayer setZPosition:kDefaultSliceZOrder];
            [pieLayer setLineWidth:0.0];
        }
    }];
    
    [self maybeNotifyDelegateOfSelectionChangeFrom:_selectedSliceIndex to:selectedIndex];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    [self touchesCancelled:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    CALayer *parentLayer = [self layer];
    NSArray *pieLayers = [parentLayer sublayers];
    
    for (CAShapeLayer *pieLayer in pieLayers) {
        [pieLayer setZPosition:kDefaultSliceZOrder];
        [pieLayer setLineWidth:0.0];
    }
}

#pragma mark - Selection Notification

- (void)maybeNotifyDelegateOfSelectionChangeFrom:(NSUInteger)previousSelection to:(NSUInteger)newSelection
{
    if (previousSelection != newSelection) {
    
        if (previousSelection != -1) {
            [_delegate pieView:self willDeselectSliceAtIndex:previousSelection];
        }

        _selectedSliceIndex = newSelection;
        
        if (newSelection != -1) {
            [_delegate pieView:self willSelectSliceAtIndex:newSelection];
            
            if (previousSelection != -1) {
                [_delegate pieView:self didDeselectSliceAtIndex:previousSelection];
            }
            
            [_delegate pieView:self didSelectSliceAtIndex:newSelection];
        } else {
            if (previousSelection != -1) {
                [_delegate pieView:self didDeselectSliceAtIndex:previousSelection];
            }
        }
    }
}

#pragma mark - Pie Layer Creation Method

- (CAShapeLayer *)createPieLayerWithColor:(UIColor *)color
{
    CAShapeLayer *pieLayer = [CAShapeLayer layer];     
    [pieLayer setZPosition:kDefaultSliceZOrder];

    [pieLayer setFillColor:color.CGColor]; 
    [pieLayer setStrokeColor:NULL];
    [pieLayer setDelegate:_addAnimationDelegate];
    
    CATextLayer *textLayer = [CATextLayer layer];
    CGFontRef font = CGFontCreateWithFontName((__bridge CFStringRef)[[UIFont boldSystemFontOfSize:17.0] fontName]);
    [textLayer setFont:font];
    CFRelease(font);
    [textLayer setFontSize:17.0];
    [textLayer setAnchorPoint:CGPointMake(0.5, 0.5)];
    [textLayer setAlignmentMode:kCAAlignmentCenter];
    [textLayer setBackgroundColor:[UIColor clearColor].CGColor];
    
    CGSize size = [self sizeThatFitsString:@"N/A"];
    
    CGFloat halfRadius = (_radius / 2);
    
    // We do not want an implicit transaction... just move to the new position
    [CATransaction setDisableActions:YES];
    [textLayer setFrame:CGRectMake(0, 0, size.width, size.height)];
    [textLayer setPosition:CGPointMake(_center.x + (halfRadius * cos(0)), _center.y + (halfRadius * sin(0)))];
    [CATransaction setDisableActions:NO];
    
    [pieLayer addSublayer:textLayer];
    return pieLayer;
}


#pragma mark - String Size Helpers

// Helper method that returns a "best fit" CGSize for the given string (assumed System font, 17pt).
- (CGSize)sizeThatFitsString:(NSString *)string
{
    if (_labelForStringSizing == nil) {
        _labelForStringSizing = [[UILabel alloc] init];
        [_labelForStringSizing setFont:[UIFont boldSystemFontOfSize:17.0]];
    }
    
    [_labelForStringSizing setText:string];
    CGSize size = [_labelForStringSizing sizeThatFits:CGSizeZero];
    [_labelForStringSizing setText:nil];
    return size;
}

- (void)updateLabelForLayer:(CAShapeLayer *)pieLayer value:(CGFloat)value
{
    NSString *label = [NSString stringWithFormat:@"%0.0f", value];
    CGSize size = [self sizeThatFitsString:label];
    
    CATextLayer *textLayer = [[pieLayer sublayers] objectAtIndex:0];
    [textLayer setString:label];
    [textLayer setBounds:CGRectMake(0, 0, size.width, size.height)];
}

@end

#pragma mark - Existing Layer Animation Delegate

@implementation BTSArcLayerDefaultAnimationDelegate

@synthesize pieView = _pieView;

// The given key path is either the kBTSArcLayerEndAngle or kBTSArcLayerStartAngle
- (id<CAAction>)createArcAnimation:(CALayer *)layer withKeyPath:(NSString *)keyPath
{
    CABasicAnimation *arcAnimation = [CABasicAnimation animationWithKeyPath:keyPath];
    
    NSNumber *modelAngle = [layer valueForKey:keyPath];
    NSNumber *currentAngle = [[layer presentationLayer] valueForKey:keyPath];
    NSComparisonResult result = [modelAngle compare:currentAngle];
    if (result != NSOrderedSame) {
        [arcAnimation setFromValue:currentAngle];
    } else {
        [arcAnimation setFromValue:[layer valueForKey:keyPath]]; 
    }
    
    [arcAnimation setDelegate:_pieView];
    [arcAnimation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
    
    return arcAnimation;
}

- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if ([kBTSArcLayerEndAngle isEqual:event]) {
        return [self createArcAnimation:layer withKeyPath:event];
    } else if ([kBTSArcLayerStartAngle isEqual:event]) {
        return [self createArcAnimation:layer withKeyPath:event];
    } else {
        return nil;
    }
}

@end

#pragma mark - New Layer Animation Delegate

@implementation BTSArcLayerAddAnimationDelegate

@synthesize pieView = _pieView;

// The given key path is either the kBTSArcLayerEndAngle or kBTSArcLayerStartAngle
- (id<CAAction>)actionForLayer:(CALayer *)layer forKey:(NSString *)event
{
    if ([kBTSArcLayerStartAngle isEqualToString:event]) {
        CABasicAnimation *startAngleAnimation = [CABasicAnimation animationWithKeyPath:kBTSArcLayerStartAngle];
        
        [startAngleAnimation setFromValue:[layer valueForKey:kBTSArcLayerEndAngle]]; 
        [startAngleAnimation setToValue:[layer valueForKey:kBTSArcLayerStartAngle]];         
        [startAngleAnimation setDelegate:_pieView];
        [startAngleAnimation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionDefault]];
                
        return startAngleAnimation;
    } else {
        return nil;
    }
}

@end




