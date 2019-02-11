//
//  GMAlbumsViewController.m
//  GMPhotoPicker
//
//  Created by Guillermo Muntaner Perelló on 19/09/14.
//  Copyright (c) 2014 Guillermo Muntaner Perelló. All rights reserved.
//

#import "GMImagePickerController.h"
#import "GMAlbumsViewController.h"
#import "GMGridViewCell.h"
#import "GMGridViewController.h"
#import "GMAlbumsViewCell.h"

#import <Photos/PHAsset.h>
#import <Photos/PHFetchOptions.h>
#import <Photos/PHImageManager.h>
#import <Photos/PHFetchResult.h>
#import <Photos/PHCollection.h>
#import <Photos/PHChange.h>


@interface GMAlbumsViewController() <PHPhotoLibraryChangeObserver>

@property (strong) NSArray *collectionsFetchResults;
@property (strong) NSArray *collectionsLocalizedTitles;
@property (strong) NSArray *collectionsFetchResultsAssets;
@property (strong) NSArray *collectionsFetchResultsTitles;
@property (nonatomic, weak) GMImagePickerController *picker;
@property (strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) NSMutableDictionary * dic_asset_fetches;

@end


@implementation GMAlbumsViewController{
    bool allow_video;
}

@synthesize dic_asset_fetches;

- (id)init:(bool)allow_v
{
    if (self = [super initWithStyle:UITableViewStylePlain])
    {
        self.preferredContentSize = kPopoverContentSize;
    }
    
    dic_asset_fetches = [[NSMutableDictionary alloc] init];
    
    allow_video = allow_v;
    
    return self;
}

static NSString * const AllPhotosReuseIdentifier = @"AllPhotosCell";
static NSString * const CollectionCellReuseIdentifier = @"CollectionCell";

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //Navigation bar customization_
    if(self.picker.customNavigationBarPrompt)
    {
        self.navigationItem.prompt = self.picker.customNavigationBarPrompt;
    }
    
    self.imageManager = [[PHCachingImageManager alloc] init];
    
    //Table view aspect
    self.tableView.rowHeight = kAlbumRowHeight;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    //Navigation bar items
    //if (self.picker.showsCancelButton)
    {
        self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(@"picker.navigation.cancel-button", @"GMImagePicker",@"Cancel")
                                         style:UIBarButtonItemStylePlain
                                        target:self.picker
                                        action:@selector(dismiss:)];
    }
    
    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc] initWithTitle:NSLocalizedStringFromTable(@"picker.navigation.done-button", @"GMImagePicker",@"Done")
                                     style:UIBarButtonItemStyleDone
                                    target:self.picker
                                    action:@selector(finishPickingAssets:)];
    
    self.navigationItem.rightBarButtonItem.enabled = (self.picker.selectedAssets.count > 0);
    
    //Bottom toolbar
    self.toolbarItems = self.picker.toolbarItems;
    
    //Title
    if (!self.picker.title)
    self.title = NSLocalizedStringFromTable(@"picker.navigation.title", @"GMImagePicker",@"Navigation bar default title");
    else
    self.title = self.picker.title;
    
    
    // TO-DO Customizable predicates:
    // Predicate has to filter properties of the type of object returned by the PHFetchResult:
    // PHCollectionList, PHAssetCollection and PHAsset require different predicates
    // with limited posibilities (cannot filter a collection by mediaType for example)
    
    //NSPredicate *predicatePHCollectionList = [NSPredicate predicateWithFormat:@"(mediaType == %d)", PHAssetMediaTypeImage];
    //NSPredicate *predicatePHAssetCollection = [NSPredicate predicateWithFormat:@"(mediaType == %d)", PHAssetMediaTypeImage];
    //NSPredicate *predicatePHAsset = [NSPredicate predicateWithFormat:@"(mediaType == %d)", PHAssetMediaTypeImage];
    
    PHFetchOptions * options = [[PHFetchOptions alloc] init];
    //NSPredicate *predicatePHAssetCollection = [NSPredicate predicateWithFormat:@"(mediaType == %d)", PHAssetMediaTypeImage];
    
    //options.predicate = predicatePHAssetCollection;
    options.sortDescriptors = @[
                                //[NSSortDescriptor sortDescriptorWithKey:@"localizedTitle" ascending:YES],
                                [ NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)],
                                ];
    
    //Fetch PHAssetCollections:
    PHFetchResult *topLevelUserCollections = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    //PHFetchResult *topLevelUserCollections = [PHCollectionList fetchTopLevelUserCollectionsWithOptions:nil];
    //PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAlbumRegular options:nil];
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    self.collectionsFetchResults = @[topLevelUserCollections, smartAlbums];
    self.collectionsLocalizedTitles = @[NSLocalizedStringFromTable(@"picker.table.user-albums-header", @"GMImagePicker",@"Albums"), NSLocalizedStringFromTable(@"picker.table.smart-albums-header", @"GMImagePicker",@"Smart Albums")];
    
    [self updateFetchResults];
    
    //Register for changes
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
}

- (void)dealloc
{
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

-(void)updateFetchResults
{
    //What I do here is fetch both the albums list and the assets of each album.
    //This way I have acces to the number of items in each album, I can load the 3
    //thumbnails directly and I can pass the fetched result to the gridViewController.
    
    NSPredicate * predicatePHAsset = allow_video? nil : [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    options.predicate = predicatePHAsset;
    
    self.collectionsFetchResultsAssets=nil;
    self.collectionsFetchResultsTitles=nil;
    
    //Fetch PHAssetCollections:
    PHFetchResult *topLevelUserCollections = [self.collectionsFetchResults objectAtIndex:0];
    PHFetchResult *smartAlbums = [self.collectionsFetchResults objectAtIndex:1];
    
    //All album: Sorted by descending creation date.
    NSMutableArray *allFetchResultArray = [[NSMutableArray alloc] init];
    NSMutableArray *allFetchResultLabel = [[NSMutableArray alloc] init];
    {
        
        PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsWithOptions:options];
        [allFetchResultArray addObject:assetsFetchResult];
        [allFetchResultLabel addObject:NSLocalizedStringFromTable(@"picker.table.all-photos-label", @"GMImagePicker",@"All photos")];
    }
    
    //User albums:
    NSMutableArray *userFetchResultArray = [[NSMutableArray alloc] init];
    NSMutableArray *userFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in topLevelUserCollections)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            //PHFetchOptions *options = [[PHFetchOptions alloc] init];
            //options.predicate = predicatePHAsset;
            PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
            
            //Albums collections are allways PHAssetCollectionType=1 & PHAssetCollectionSubtype=2
            
            PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
            [userFetchResultArray addObject:assetsFetchResult];
            [userFetchResultLabel addObject:collection.localizedTitle];
        }
    }
    
    
    //Smart albums: Sorted by descending creation date.
    NSMutableArray *smartFetchResultArray = [[NSMutableArray alloc] init];
    NSMutableArray *smartFetchResultLabel = [[NSMutableArray alloc] init];
    for(PHCollection *collection in smartAlbums)
    {
        if ([collection isKindOfClass:[PHAssetCollection class]])
        {
            PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
            
            //Smart collections are PHAssetCollectionType=2;
            if(self.picker.customSmartCollections && [self.picker.customSmartCollections containsObject:@(assetCollection.assetCollectionSubtype)])
            {
                //PHFetchOptions *options = [[PHFetchOptions alloc] init];
                //options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
                //options.predicate = predicatePHAsset;
                PHFetchResult *assetsFetchResult = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
                if(assetsFetchResult.count>0)
                {
                    [smartFetchResultArray addObject:assetsFetchResult];
                    [smartFetchResultLabel addObject:collection.localizedTitle];
                }
            }
        }
    }
    
    self.collectionsFetchResultsAssets= @[allFetchResultArray,userFetchResultArray,smartFetchResultArray];
    self.collectionsFetchResultsTitles= @[allFetchResultLabel,userFetchResultLabel,smartFetchResultLabel];
}
#pragma mark - Accessors

- (GMImagePickerController *)picker
{
    return (GMImagePickerController *)self.navigationController.parentViewController;
}


#pragma mark - Rotation

- (BOOL)shouldAutorotate
{
    return YES;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.collectionsFetchResultsAssets.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    PHFetchResult *fetchResult = self.collectionsFetchResultsAssets[section];
    return fetchResult.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    GMAlbumsViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[GMAlbumsViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    // Increment the cell's tag
    NSInteger currentTag = cell.tag + 1;
    cell.tag = currentTag;
    
    //Set the label
    cell.titleLabel.text = (self.collectionsFetchResultsTitles[indexPath.section])[indexPath.row];
    
    //Retrieve the pre-fetched assets for this album:
    PHFetchResult *assetsFetchResult = (self.collectionsFetchResultsAssets[indexPath.section])[indexPath.row];
    
    //Display the number of assets
    if(self.picker.displayAlbumsNumberOfAssets)
    {
//        cell.detailTextLabel.text = [self tableCellSubtitle:assetsFetchResult];
    }
    
    //Set the 3 images (if exists):
    if([assetsFetchResult count]>0)
    {
        CGFloat scale = [UIScreen mainScreen].scale;
        
        //Compute the thumbnail pixel size:
        CGSize tableCellThumbnailSize1 = CGSizeMake(kAlbumThumbnailSize1.width*scale, kAlbumThumbnailSize1.height*scale);
        PHAsset *asset = assetsFetchResult[0];
        [cell setVideoLayout:(asset.mediaType==PHAssetMediaTypeVideo)];
        [self.imageManager requestImageForAsset:asset
                                     targetSize:tableCellThumbnailSize1
                                    contentMode:PHImageContentModeAspectFill
                                        options:nil