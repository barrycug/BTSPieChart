//
//  BTSViewController.m
//  TouchPie
//
//  Created by Brian Coyner on 9/6/11.
//  Copyright (c) 2011 Brian Coyner. All rights reserved.
//

#import "BTSDemoViewController.h"
#import <QuartzCore/QuartzCore.h>

//
// This is a very simple view controller used to display and control a BTSPieView chart view. 
// 
// NOTE: This view controller restricts various interactions with the pie view. 
//       Specifically, there must be a valid selection to delete a pie wedge. The selection 
//       is cleared after every deletion. This keeps the user from pressing the "-" button 
//       really fast, which causes issues with this version of the BTSPieView. 
//
// Please see BTSPieChart.m for additional notes.

@interface BTSDemoViewController() <BTSPieViewDataSource, BTSPieViewDelegate> {
    
    NSMutableArray *_slices;
    NSInteger _selectedSliceIndex;

    __weak IBOutlet UIStepper *_sliceStepper;
    __weak IBOutlet UILabel *_sliceCountLabel;
   
    __weak IBOutlet UISlider *_selectedSliceValueSlider;
    __weak IBOutlet UILabel *_selectedSliceValueLabel;
    
    __weak IBOutlet UISlider *_animationSpeedSlider;
    __weak IBOutlet UILabel *_animationSpeedLabel;
}

- (IBAction)updateSliceCount:(id)sender;
- (IBAction)updateAnimationSpeed:(id)sender;
- (IBAction)updateSelectedSliceValue:(id)sender;

@end

@implementation BTSDemoViewController

@synthesize pieView = _pieView;

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // initialize the user interface with reasonable defaults
    [_animationSpeedSlider setValue:0.5];
    [self updateAnimationSpeed:_animationSpeedSlider];
    
    [_selectedSliceValueSlider setValue:0.0];
    [_selectedSliceValueSlider setEnabled:NO];
    [_selectedSliceValueLabel setAlpha:0.0];
    [self updateSelectedSliceValue:_selectedSliceValueSlider];
    
    [_sliceStepper setValue:0];
    [self updateSliceCount:_sliceStepper];

    // start with a blank slate
    _slices = [[NSMutableArray alloc] init];
    _selectedSliceIndex = -1;
    
    // set up the data source and delegate
    [_pieView setDataSource:self];
    [_pieView setDelegate:self];
    
    // Must divide by 255.0F... RBG values are between 1.0 and 0.0
    NSArray *colors = [NSArray arrayWithObjects:
                       [UIColor colorWithRed:93/255.0 green:150/255.0 blue:72/255.0 alpha:1.0], 
                       [UIColor colorWithRed:46/255.0 green:87/255.0 blue:140/255.0 alpha:1.0], 
                       [UIColor colorWithRed:231/255.0 green:161/255.0 blue:61/255.0 alpha:1.0], 
                       [UIColor colorWithRed:188/255.0 green:45/255.0 blue:48/255.0 alpha:1.0], 
                       [UIColor colorWithRed:111/255.0 green:61/255.0 blue:121/255.0 alpha:1.0], 
                       [UIColor colorWithRed:125/255.0 green:128/255.0 blue:127/255.0 alpha:1.0], 
                       [UIColor colorWithRed:65/255.0 green:105/255.0 blue:155/255.0 alpha:1.0], 
                       [UIColor colorWithRed:110/255.0 green:64/255.0 blue:190/255.0 alpha:1.0], nil];
  
    // the BTSPieView cycles through the colors. 
    [_pieView setSliceColors:colors];
    
    // tell the pie view we have data (animates)
    [_pieView reloadData];
}

- (void)viewDidUnload
{
    [_pieView setDataSource:nil];
    [_pieView setDelegate:nil];
    
    _sliceStepper = nil;
    _sliceCountLabel = nil;
    _selectedSliceValueSlider = nil;
    _selectedSliceValueLabel = nil;
    _animationSpeedSlider = nil;
    _animationSpeedLabel = nil;

    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return UIInterfaceOrientationIsPortrait(interfaceOrientation);
}

#pragma mark - BTSPieView Data Source

- (NSUInteger)numberOfSlicesInPieView:(BTSPieView *)pieView
{
    return [_slices count];
}

- (double)pieView:(BTSPieView *)pieView valueForSliceAtIndex:(NSUInteger)index
{
    return [[_slices objectAtIndex:index] doubleValue];
}

#pragma mark - BTSPieView Delegate

- (void)pieView:(BTSPieView *)pieView willSelectSliceAtIndex:(NSUInteger)index
{
    NSLog(@"willSelectSliceAtIndex: %d", index);
}

- (void)pieView:(BTSPieView *)pieView didSelectSliceAtIndex:(NSUInteger)index
{
    NSLog(@"didSelectSliceAtIndex: %d", index);  
    
    // save the index the user selected.
    _selectedSliceIndex = index;
    
    // update the selected slice UI components with the model values
    [_selectedSliceValueLabel setText:[NSString stringWithFormat:@"%@", [_slices objectAtIndex:index]]];
    [_selectedSliceValueSlider setValue:[[_slices objectAtIndex:index] floatValue]];
    
    // To help the user track slice selection we change the track color to be the same color as the selected slice.
    // The pie layers are not exposed... but for this demo we will just grab them using our intimate knowledge
    // of the BTSPieView.
    
    CAShapeLayer *selectedLayer = [[[_pieView layer] sublayers] objectAtIndex:index];
    UIColor *sliceColor = [UIColor colorWithCGColor:[selectedLayer fillColor]];

    [_selectedSliceValueSlider setEnabled:YES];
    [_selectedSliceValueSlider setMinimumTrackTintColor:sliceColor];
    [_selectedSliceValueSlider setMaximumTrackTintColor:sliceColor];
    [_selectedSliceValueLabel setAlpha:1.0];
}

- (void)pieView:(BTSPieView *)pieView willDeselectSliceAtIndex:(NSUInteger)index
{
    NSLog(@"willDeselectSliceAtIndex: %d", index);   
}

- (void)pieView:(BTSPieView *)pieView didDeselectSliceAtIndex:(NSUInteger)index
{
    NSLog(@"didDeselectSliceAtIndex: %d", index);  
    [_selectedSliceValueSlider setMinimumTrackTintColor:nil];
    [_selectedSliceValueSlider setMaximumTrackTintColor:nil];
    
    // nothing is selected... so turn off the "selected value" controls
    _selectedSliceIndex = -1;
    [_selectedSliceValueSlider setEnabled:NO];
    [_selectedSliceValueSlider setValue:0.0];
    [_selectedSliceValueLabel setAlpha:0.0];
 
    [self updateSelectedSliceValue:_selectedSliceValueSlider];
}

#pragma mark - UI Controls To Manipulate

- (IBAction)updateSliceCount:(id)sender {
    
    UIStepper *stepper = (UIStepper *)sender;
    NSUInteger sliceCount = (NSUInteger) [stepper value];
    
    [_sliceCountLabel setText:[NSString stringWithFormat:@"%d", sliceCount]];
    
    if ([_slices count] < sliceCount) { // "+" pressed
        
        // add a new value and tell the pie view to reload (this animates).
        [_slices addObject:[NSNumber numberWithDouble:10.0]];        
        [_pieView reloadData];
    } else if ([_slices count] > sliceCount) { // "-" pressed

        // The user wants to remove the selected layer. We only allow the user to remove a selected layer
        // if there is a known selection.
        if (_selectedSliceIndex > -1) {

            [_slices removeObjectAtIndex:_selectedSliceIndex];
            
            // As mentioned in the class level notes, any time a wedge is deleted the view controller's
            // selection index is set to -1 (no selection). This keeps the user from pressing the "-" 
            // stepper button really fast and causing the pie view to go nuts. Yes, this is a problem 
            // with this version of the BTSPieView.
            _selectedSliceIndex = -1;

            [_pieView reloadData];
        } else {
            
            // no selection... reset the stepper... no need to reload the pie view.
            [_sliceStepper setValue:sliceCount + 1];
            [self updateSliceCount:_sliceStepper];
        }
    }
}

- (IBAction)updateAnimationSpeed:(id)sender {
    
    UISlider *slider = (UISlider *)sender;
    float animationSpeed = [slider value];
    [_animationSpeedLabel setText:[NSString stringWithFormat:@"%f", animationSpeed]];
    [_pieView setAnimationSpeed:animationSpeed];

}

- (IBAction)updateSelectedSliceValue:(id)sender {
    
    int value = (int)[_selectedSliceValueSlider value];
    [_selectedSliceValueLabel setText:[NSString stringWithFormat:@"%d", value]];
    
    if (_selectedSliceIndex != -1) {
        NSNumber *newValue = [NSNumber numberWithDouble:value];
        [_slices replaceObjectAtIndex:_selectedSliceIndex withObject:newValue];
        
        [_pieView reloadData];
    }
}

@end
