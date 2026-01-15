//
//  Metal.m
//  OpenParsec
//
//  Created by user on 2026/1/14.
//



#import "Metal.h"
#import <QuartzCore/CAMetalLayer.h>


@interface ParsecMetalBridge ()
@property (nonatomic, assign) void *parsec;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> queue;


@end

@implementation ParsecMetalBridge

- (instancetype)initWithParsec:(void *)parsecInstance
						 device:(id<MTLDevice>)device
					 {
	self = [super init];
	if (self) {
		_parsec = parsecInstance;
		_device = device;
		_queue = [device newCommandQueue];

	}
	return self;
}

- (ParsecStatus)renderIntoDrawable:(id)drawable
						   timeout:(uint32_t)timeout {

	// 在 .m 內轉型
	id<CAMetalDrawable> metalDrawable = (id<CAMetalDrawable>)drawable;
	id<MTLTexture> tex = metalDrawable.texture;

	ParsecMetalTexture *t =
		(__bridge ParsecMetalTexture *)tex;


	ParsecStatus status = ParsecClientMetalRenderFrame(
		_parsec,
		0,
 // DEFAULT_STREAM
													   (__bridge ParsecMetalCommandQueue *)(_queue),
		&t,
		NULL,
		NULL,
		timeout
	);

	// SDK 可能更新 texture
	// 更新 _texture

	// 3️⃣ 更新 _texture 指向最新 texture


	return status;
}



@end
