//
//  MPEntities.m
//  MasterPassword-iOS
//
//  Created by Maarten Billemont on 31/05/12.
//  Copyright (c) 2012 Lyndir. All rights reserved.
//

#import "MPEntities.h"
#import "MPAppDelegate_Shared.h"
#import "MPAppDelegate_Key.h"
#import "MPAppDelegate_InApp.h"

@implementation NSManagedObjectContext(MP)

- (BOOL)saveToStore {

    __block BOOL success = YES;
    if ([self hasChanges]) {
        [self performBlockAndWait:^{
            @try {
                NSError *error = nil;
                if (!(success = [self save:&error]))
                    err( @"While saving: %@", [error fullDescription] );
            }
            @catch (NSException *exception) {
                success = NO;
                err( @"While saving: %@", [exception fullDescription] );
            }
        }];
    }

    return success && (!self.parentContext || [self.parentContext saveToStore]);
}

@end

@implementation MPSiteQuestionEntity(MP)

- (NSString *)resolveQuestionAnswerUsingKey:(MPKey *)key {

    return [self.site.algorithm resolveAnswerForQuestion:self usingKey:key];
}

- (void)resolveQuestionAnswerUsingKey:(MPKey *)key result:(void ( ^ )(NSString *))result {

    [self.site.algorithm resolveAnswerForQuestion:self usingKey:key result:result];
}

@end

@implementation MPSiteEntity(MP)

- (MPFixableResult)findAndFixInconsistenciesInContext:(NSManagedObjectContext *)context {

    return MPFixableResultNoProblems;
}

- (MPSiteType)type {

    return (MPSiteType)[self.type_ unsignedIntegerValue];
}

- (void)setLoginGenerated:(BOOL)aLoginGenerated {

    self.loginGenerated_ = @(aLoginGenerated);
}

- (BOOL)loginGenerated {

    return [self.loginGenerated_ boolValue];
}

- (void)setType:(MPSiteType)aType {

    self.type_ = @(aType);
}

- (NSString *)typeName {

    return [self.algorithm nameOfType:self.type];
}

- (NSString *)typeShortName {

    return [self.algorithm shortNameOfType:self.type];
}

- (NSString *)typeClassName {

    return [self.algorithm classNameOfType:self.type];
}

- (Class)typeClass {

    return [self.algorithm classOfType:self.type];
}

- (NSUInteger)uses {

    return [self.uses_ unsignedIntegerValue];
}

- (void)setUses:(NSUInteger)anUses {

    self.uses_ = @(anUses);
}

- (id<MPAlgorithm>)algorithm {

    return MPAlgorithmForVersion(
            MIN( MPAlgorithmVersionCurrent,
                    MAX( MPAlgorithmVersion0, (MPAlgorithmVersion)[self.version_ unsignedIntegerValue] ) ) );
}

- (void)setAlgorithm:(id<MPAlgorithm>)algorithm {

    self.version_ = @([algorithm version]);
}

- (BOOL)requiresExplicitMigration {

    return [self.requiresExplicitMigration_ boolValue];
}

- (void)setRequiresExplicitMigration:(BOOL)requiresExplicitMigration {

    self.requiresExplicitMigration_ = @(requiresExplicitMigration);
}

- (NSUInteger)use {

    self.lastUsed = [NSDate date];
    return ++self.uses;
}

- (NSString *)description {

    return strf( @"%@:%@", [self class], [self name] );
}

- (NSString *)debugDescription {

    __block NSString *debugDescription = strf( @"{%@: [recursing]}", [self class] );

    static BOOL recursing = NO;
    PearlIfNotRecursing( &recursing, ^{
        @try {
            debugDescription = strf(
                    @"{%@: name=%@, user=%@, type=%lu, uses=%ld, lastUsed=%@, version=%ld, loginName=%@, requiresExplicitMigration=%d}",
                    NSStringFromClass( [self class] ), self.name, self.user.name, (long)self.type, (long)self.uses, self.lastUsed,
                    (long)[self.algorithm version],
                    self.loginName, self.requiresExplicitMigration );
        }
        @catch (NSException *exception) {
            debugDescription = strf( @"{%@: inaccessible: %@}",
                    NSStringFromClass( [self class] ), [exception fullDescription] );
        }
    } );

    return debugDescription;
}

- (BOOL)tryMigrateExplicitly:(BOOL)explicit {

    MPAlgorithmVersion algorithmVersion;
    while ((algorithmVersion = [self.algorithm version]) < MPAlgorithmDefaultVersion) {
        MPAlgorithmVersion toVersion = algorithmVersion + 1;
        if (![MPAlgorithmForVersion( toVersion ) tryMigrateSite:self explicit:explicit]) {
            wrn( @"%@ migration to version: %ld failed for site: %@",
                    explicit? @"Explicit": @"Automatic", (long)toVersion, self );
            return NO;
        }

        inf( @"%@ migration to version: %ld succeeded for site: %@",
                explicit? @"Explicit": @"Automatic", (long)toVersion, self );
    }

    return YES;
}

- (NSString *)resolveLoginUsingKey:(MPKey *)key {

    return [self.algorithm resolveLoginForSite:self usingKey:key];
}

- (NSString *)resolvePasswordUsingKey:(MPKey *)key {

    return [self.algorithm resolvePasswordForSite:self usingKey:key];
}

- (NSString *)resolveSiteAnswerUsingKey:(MPKey *)key {

    return [self.algorithm resolveAnswerForSite:self usingKey:key];
}

- (void)resolveLoginUsingKey:(MPKey *)key result:(void ( ^ )(NSString *))result {

    [self.algorithm resolveLoginForSite:self usingKey:key result:result];
}

- (void)resolvePasswordUsingKey:(MPKey *)key result:(void ( ^ )(NSString *))result {

    [self.algorithm resolvePasswordForSite:self usingKey:key result:result];
}

- (void)resolveSiteAnswerUsingKey:(MPKey *)key result:(void ( ^ )(NSString *))result {

    [self.algorithm resolveAnswerForSite:self usingKey:key result:result];
}

- (void)resolveAnswerUsingKey:(MPKey *)key forQuestion:(NSString *)question result:(void ( ^ )(NSString *))result {

    MPSiteQuestionEntity *questionEntity = [MPSiteQuestionEntity new];
    questionEntity.site = self;
    questionEntity.keyword = question;
    [questionEntity resolveQuestionAnswerUsingKey:key result:result];
}

@end

@implementation MPGeneratedSiteEntity(MP)

- (MPFixableResult)findAndFixInconsistenciesInContext:(NSManagedObjectContext *)context {

    MPFixableResult result = [super findAndFixInconsistenciesInContext:context];

    if (!self.type || self.type == (MPSiteType)NSNotFound || ![[self.algorithm allTypes] containsObject:self.type_])
        // Invalid self.type
        result = MPApplyFix( result, ^MPFixableResult {
            wrn( @"Invalid type for: %@ of %@, type: %ld.  Will use %ld instead.",
                    self.name, self.user.name, (long)self.type, (long)self.user.defaultType );
            self.type = self.user.defaultType;
            return MPFixableResultProblemsFixed;
        } );
    if (!self.type || self.type == (MPSiteType)NSNotFound || ![[self.algorithm allTypes] containsObject:self.type_])
        // Invalid self.user.defaultType
        result = MPApplyFix( result, ^MPFixableResult {
            wrn( @"Invalid type for: %@ of %@, type: %ld.  Will use %ld instead.",
                    self.name, self.user.name, (long)self.type, (long)MPSiteTypeGeneratedLong );
            self.type = MPSiteTypeGeneratedLong;
            return MPFixableResultProblemsFixed;
        } );
    if (![self isKindOfClass:[self.algorithm classOfType:self.type]])
        // Mismatch between self.type and self.class
        result = MPApplyFix( result, ^MPFixableResult {
            for (MPSiteType newType = self.type; self.type != (newType = [self.algorithm nextType:newType]);)
                if ([self isKindOfClass:[self.algorithm classOfType:newType]]) {
                    wrn( @"Mismatching type for: %@ of %@, type: %lu, class: %@.  Will use %ld instead.",
                            self.name, self.user.name, (long)self.type, self.class, (long)newType );
                    self.type = newType;
                    return MPFixableResultProblemsFixed;
                }

            err( @"Mismatching type for: %@ of %@, type: %lu, class: %@.  Couldn't find a type to fix problem with.",
                    self.name, self.user.name, (long)self.type, self.class );
            return MPFixableResultProblemsNotFixed;
        } );

    return result;
}

- (NSUInteger)counter {

    return [self.counter_ unsignedIntegerValue];
}

- (void)setCounter:(NSUInteger)aCounter {

    self.counter_ = @(aCounter);
}

@end

@implementation MPStoredSiteEntity(MP)

- (MPFixableResult)findAndFixInconsistenciesInContext:(NSManagedObjectContext *)context {

    MPFixableResult result = [super findAndFixInconsistenciesInContext:context];

    if (self.contentObject && ![self.contentObject isKindOfClass:[NSData class]])
        result = MPApplyFix( result, ^MPFixableResult {
            MPKey *key = [MPAppDelegate_Shared get].key;
            if (key && [[MPAppDelegate_Shared get] activeUserInContext:context] == self.user) {
                wrn( @"Content object not encrypted for: %@ of %@.  Will re-encrypt.", self.name, self.user.name );
                [self.algorithm savePassword:[self.contentObject description] toSite:self usingKey:key];
                return MPFixableResultProblemsFixed;
            }

            err( @"Content object not encrypted for: %@ of %@.  Couldn't fix, please sign in.", self.name, self.user.name );
            return MPFixableResultProblemsNotFixed;
        } );

    return result;
}

@end

@implementation MPUserEntity(MP)

- (NSUInteger)avatar {

    return [self.avatar_ unsignedIntegerValue];
}

- (void)setAvatar:(NSUInteger)anAvatar {

    self.avatar_ = @(anAvatar);
}

- (BOOL)saveKey {

    return [self.saveKey_ boolValue];
}

- (void)setSaveKey:(BOOL)aSaveKey {

    self.saveKey_ = @(aSaveKey);
}

- (BOOL)touchID {

    return [self.touchID_ boolValue] && [[MPAppDelegate_Shared get] isFeatureUnlocked:MPProductTouchID];
}

- (void)setTouchID:(BOOL)aTouchID {

    self.touchID_ = @(aTouchID);
}

- (MPSiteType)defaultType {

    return (MPSiteType)[self.defaultType_ unsignedIntegerValue]?: MPSiteTypeGeneratedLong;
}

- (void)setDefaultType:(MPSiteType)aDefaultType {

    self.defaultType_ = @(aDefaultType);
}

- (id<MPAlgorithm>)algorithm {

    return MPAlgorithmForVersion(
            MIN( MPAlgorithmVersionCurrent,
                    MAX( MPAlgorithmVersion0, (MPAlgorithmVersion)[self.version_ unsignedIntegerValue] ) ) );
}

- (void)setAlgorithm:(id<MPAlgorithm>)version {

    self.version_ = @([version version]);
    [[MPAppDelegate_Shared get] forgetSavedKeyFor:self];
}

- (NSString *)userID {

    return [MPUserEntity idFor:self.name];
}

+ (NSString *)idFor:(NSString *)userName {

    return [[userName hashWith:PearlHashSHA1] encodeHex];
}

@end
