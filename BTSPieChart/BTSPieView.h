//
//  BTSPieView.h
//  TouchPie
//
//  Created by Brian Coyner on 9/9/11.
//  Copyright (c) 2011 Brian Coyner. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CAMediaTimingFunction;

@protocol BTSPieViewDataSource;
@protocol BTSPieViewDelegate;

@interface BTSPieView : UIView

@property (nonatomic, assign) id<BTSPieViewDataSource> dataSource;
@property (nonatomic, assign) id<BTSPieViewDelegate> delegate;

@property (nonatomic, assign) CGFloat animationSpeed;
@property (nonatomic, copy) NSArray *sliceColors;

// causes the pie chart to recalculate the slices (and animate)
- (void)reloadData;

@end

@protocol BTSPieViewDataSource <NSObject>

- (NSUInteger)numberOfSlicesInPieView:(BTSPieView *)pieView;
- (double)pieView:(BTSPieView *)pieView valueForSliceAtIndex:(NSUInteger)index;
@end 

@protocol BTSPieViewDelegate <NSObject>

- (void)pieView:(BTSPieView *)pieView willSelectSliceAtIndex:(NSUInteger)index;
- (void)pieView:(BTSPieView *)pieView didSelectSliceAtIndex:(NSUInteger)index;

- (void)pieView:(BTSPieView *)pieView willDeselectSliceAtIndex:(NSUInteger)index;
- (void)pieView:(BTSPieView *)pieView didDeselectSliceAtIndex:(NSUInteger)index;

@end
