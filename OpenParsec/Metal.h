//
//  Metal.h
//  OpenParsec
//
//  Created by user on 2026/1/14.
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <ParsecSDK/parsec.h>

#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface ParsecMetalBridge : NSObject

// 初始化时传入 Parsec SDK 实例和 MTLDevice
- (instancetype)initWithParsec:(void *)parsecInstance
						 device:(id<MTLDevice>)device;


// 直接渲染一帧，不需要从外部传 queue/texture
- (ParsecStatus)renderIntoDrawable:(id)drawable
						   timeout:(uint32_t)timeout;



@end

NS_ASSUME_NONNULL_END
