const std = @import("std");

pub fn Module(
    comptime AccountKey: type,
    comptime CredentialKind: type,
    comptime Credential: type,
    comptime LoadError: type,
    comptime SaveError: type,
    comptime RemoveError: type,
    comptime CredentialStore: type,
    comptime max_account_label_bytes: usize,
    comptime max_credential_bytes: usize,
    comptime accountLabel: anytype,
) type {
    return struct {
        pub const ItemClass = enum {
            generic_password,

            internet_password,
        };

        pub const Accessibility = enum {
            when_unlocked_this_device_only,
        };

        pub const AuthenticationUI = enum { fail, allow };

        pub const ItemQuery = struct {
            class: ItemClass = .generic_password,

            service: []const u8,

            account: []const u8,
            accessibility: Accessibility = .when_unlocked_this_device_only,
            synchronizable: bool = false,
            authentication_ui: AuthenticationUI = .fail,

            pub fn isSelfOwned(self: ItemQuery) bool {
                return self.class == .generic_password and
                    !self.synchronizable and
                    self.accessibility == .when_unlocked_this_device_only and
                    (std.mem.eql(u8, self.service, macos.v2_service) or
                        std.mem.eql(u8, self.service, macos.legacy_service));
            }

            pub fn isWritableV2(self: ItemQuery) bool {
                return self.isSelfOwned() and std.mem.eql(u8, self.service, macos.v2_service);
            }
        };

        pub const macos = struct {
            pub const app_service_prefix = "dev.codexmulti.app";
            pub const legacy_service = app_service_prefix;
            pub const v2_service = app_service_prefix ++ ".v2";
            pub const default_service = v2_service;
            pub const stable_designated_requirement =
                "identifier \"dev.codexmulti.app\" and certificate root = H\"348b6cf6eed9f518a04c89f02cca7cd91674c55d\"";

            pub const SecItemBackend = struct {
                context: *anyopaque,
                vtable: *const VTable,

                pub const VTable = struct {
                    copy: *const fn (context: *anyopaque, query: ItemQuery, out: *Credential) LoadError!void,
                    exists: *const fn (context: *anyopaque, query: ItemQuery) LoadError!bool,
                    upsert: *const fn (context: *anyopaque, query: ItemQuery, credential: *const Credential) SaveError!void,
                    delete: *const fn (context: *anyopaque, query: ItemQuery) RemoveError!void,
                };
            };

            pub const OSStatus = i32;

            pub const status_success: OSStatus = 0;
            pub const status_unimplemented: OSStatus = -4;
            pub const status_disk_full: OSStatus = -34;
            pub const status_io: OSStatus = -36;
            pub const status_param: OSStatus = -50;
            pub const status_allocate: OSStatus = -108;
            pub const status_user_canceled: OSStatus = -128;
            pub const status_not_available: OSStatus = -25291;
            pub const status_read_only: OSStatus = -25292;
            pub const status_auth_failed: OSStatus = -25293;
            pub const status_no_such_keychain: OSStatus = -25294;
            pub const status_invalid_keychain: OSStatus = -25295;
            pub const status_duplicate_item: OSStatus = -25299;
            pub const status_item_not_found: OSStatus = -25300;
            pub const status_buffer_too_small: OSStatus = -25301;
            pub const status_data_too_large: OSStatus = -25302;
            pub const status_interaction_not_allowed: OSStatus = -25308;
            pub const status_decode: OSStatus = -26275;
            pub const status_missing_entitlement: OSStatus = -34018;

            pub fn loadErrorFromStatus(status: OSStatus) LoadError {
                return switch (status) {
                    status_item_not_found, status_no_such_keychain => error.NotFound,
                    status_user_canceled,
                    status_missing_entitlement,
                    => error.AccessDenied,
                    status_auth_failed, status_interaction_not_allowed => error.RepairRequired,
                    status_not_available,
                    status_allocate,
                    => error.Unavailable,
                    status_data_too_large, status_buffer_too_small => error.ValueTooLarge,
                    status_decode, status_invalid_keychain, status_param => error.Corrupt,

                    status_unimplemented => error.Unsupported,
                    else => error.Io,
                };
            }

            pub fn saveErrorFromStatus(status: OSStatus) SaveError {
                return switch (status) {
                    status_user_canceled,
                    status_missing_entitlement,
                    status_read_only,
                    => error.AccessDenied,
                    status_auth_failed, status_interaction_not_allowed => error.RepairRequired,
                    status_not_available,
                    status_allocate,
                    status_no_such_keychain,
                    => error.Unavailable,
                    status_data_too_large, status_buffer_too_small => error.ValueTooLarge,
                    status_disk_full => error.StoreFull,
                    status_unimplemented => error.Unsupported,
                    else => error.Io,
                };
            }

            pub fn removeErrorFromStatus(status: OSStatus) RemoveError {
                return switch (status) {
                    status_user_canceled,
                    status_missing_entitlement,
                    status_read_only,
                    => error.AccessDenied,
                    status_auth_failed, status_interaction_not_allowed => error.RepairRequired,
                    status_not_available,
                    status_allocate,
                    status_no_such_keychain,
                    => error.Unavailable,
                    status_unimplemented => error.Unsupported,
                    else => error.Io,
                };
            }

            pub const SecItemApi = struct {
                context: *anyopaque,
                vtable: *const VTable,

                pub const VTable = struct {
                    copy: *const fn (context: *anyopaque, query: ItemQuery, out: *Credential) OSStatus,

                    matches: *const fn (context: *anyopaque, query: ItemQuery) OSStatus,

                    add: *const fn (context: *anyopaque, query: ItemQuery, credential: *const Credential) OSStatus,

                    update: *const fn (context: *anyopaque, query: ItemQuery, credential: *const Credential) OSStatus,

                    delete: *const fn (context: *anyopaque, query: ItemQuery) OSStatus,
                };
            };

            pub const SecItemStore = struct {
                api: SecItemApi,

                const vtable: SecItemBackend.VTable = .{
                    .copy = copy,
                    .exists = exists,
                    .upsert = upsert,
                    .delete = delete,
                };

                pub fn init(api: SecItemApi) SecItemStore {
                    return .{ .api = api };
                }

                pub fn backend(self: *SecItemStore) SecItemBackend {
                    return .{ .context = self, .vtable = &vtable };
                }

                fn copy(context: *anyopaque, query: ItemQuery, out: *Credential) LoadError!void {
                    const self: *SecItemStore = @ptrCast(@alignCast(context));
                    if (!query.isSelfOwned()) return error.AccessDenied;
                    const status = self.api.vtable.copy(self.api.context, query, out);
                    if (status != status_success) return loadErrorFromStatus(status);
                }

                fn exists(context: *anyopaque, query: ItemQuery) LoadError!bool {
                    const self: *SecItemStore = @ptrCast(@alignCast(context));
                    if (!query.isSelfOwned()) return error.AccessDenied;
                    const status = self.api.vtable.matches(self.api.context, query);
                    if (status == status_success) return true;
                    if (status == status_item_not_found) return false;
                    return loadErrorFromStatus(status);
                }

                fn upsert(context: *anyopaque, query: ItemQuery, credential: *const Credential) SaveError!void {
                    const self: *SecItemStore = @ptrCast(@alignCast(context));
                    if (!query.isSelfOwned()) return error.AccessDenied;
                    if (credential.length() > max_credential_bytes) return error.ValueTooLarge;

                    const updated = self.api.vtable.update(self.api.context, query, credential);
                    if (updated == status_success) return;
                    if (updated != status_item_not_found) return saveErrorFromStatus(updated);

                    const added = self.api.vtable.add(self.api.context, query, credential);
                    if (added == status_success) return;

                    if (added != status_duplicate_item) return saveErrorFromStatus(added);
                    const retried = self.api.vtable.update(self.api.context, query, credential);
                    if (retried == status_success) return;
                    return saveErrorFromStatus(retried);
                }

                fn delete(context: *anyopaque, query: ItemQuery) RemoveError!void {
                    const self: *SecItemStore = @ptrCast(@alignCast(context));
                    if (!query.isSelfOwned()) return error.AccessDenied;
                    const status = self.api.vtable.delete(self.api.context, query);
                    if (status == status_success or status == status_item_not_found) return;
                    return removeErrorFromStatus(status);
                }
            };

            pub const KeychainStore = struct {
                service: []const u8,
                authentication_ui: AuthenticationUI = .fail,
                backend: ?SecItemBackend = null,

                const vtable: CredentialStore.VTable = .{
                    .load = load,
                    .contains = contains,
                    .save = save,
                    .remove = remove,
                };

                pub fn init(service: []const u8) error{ForeignKeychainService}!KeychainStore {
                    if (!std.mem.eql(u8, service, v2_service) and !std.mem.eql(u8, service, legacy_service)) {
                        return error.ForeignKeychainService;
                    }
                    return .{ .service = service };
                }

                pub fn initForSignIn(service: []const u8) error{ForeignKeychainService}!KeychainStore {
                    if (!std.mem.eql(u8, service, v2_service)) return error.ForeignKeychainService;
                    return .{ .service = service, .authentication_ui = .allow };
                }

                pub fn store(self: *KeychainStore) CredentialStore {
                    return .{ .context = self, .vtable = &vtable };
                }

                pub fn isWired(self: *const KeychainStore) bool {
                    return self.backend != null;
                }

                pub fn query(
                    self: *const KeychainStore,
                    account: *const AccountKey,
                    kind: CredentialKind,
                    buffer: []u8,
                ) error{BufferTooSmall}!ItemQuery {
                    return .{
                        .service = self.service,
                        .account = try accountLabel(account, kind, buffer),
                        .authentication_ui = self.authentication_ui,
                    };
                }

                fn load(context: *anyopaque, account: *const AccountKey, kind: CredentialKind, out: *Credential) LoadError!void {
                    const self: *KeychainStore = @ptrCast(@alignCast(context));
                    const backend = self.backend orelse return error.Unsupported;
                    var buffer: [max_account_label_bytes]u8 = undefined;
                    const item = self.query(account, kind, &buffer) catch return error.Corrupt;
                    if (!item.isSelfOwned()) return error.AccessDenied;
                    return backend.vtable.copy(backend.context, item, out);
                }

                fn contains(context: *anyopaque, account: *const AccountKey, kind: CredentialKind) LoadError!bool {
                    const self: *KeychainStore = @ptrCast(@alignCast(context));
                    const backend = self.backend orelse return error.Unsupported;
                    var buffer: [max_account_label_bytes]u8 = undefined;
                    const item = self.query(account, kind, &buffer) catch return error.Corrupt;
                    if (!item.isSelfOwned()) return error.AccessDenied;
                    return backend.vtable.exists(backend.context, item);
                }

                fn save(context: *anyopaque, account: *const AccountKey, kind: CredentialKind, credential: *const Credential) SaveError!void {
                    const self: *KeychainStore = @ptrCast(@alignCast(context));
                    const backend = self.backend orelse return error.Unsupported;
                    if (credential.length() > max_credential_bytes) return error.ValueTooLarge;
                    var buffer: [max_account_label_bytes]u8 = undefined;
                    const item = self.query(account, kind, &buffer) catch return error.ValueTooLarge;
                    if (!item.isSelfOwned()) return error.AccessDenied;
                    return backend.vtable.upsert(backend.context, item, credential);
                }

                fn remove(context: *anyopaque, account: *const AccountKey, kind: CredentialKind) RemoveError!void {
                    const self: *KeychainStore = @ptrCast(@alignCast(context));
                    const backend = self.backend orelse return error.Unsupported;
                    var buffer: [max_account_label_bytes]u8 = undefined;
                    const item = self.query(account, kind, &buffer) catch return error.Io;
                    if (!item.isSelfOwned()) return error.AccessDenied;
                    return backend.vtable.delete(backend.context, item);
                }
            };

            pub const VersionedKeychainStore = struct {
                primary: CredentialStore,
                legacy: CredentialStore,

                const vtable: CredentialStore.VTable = .{
                    .load = load,
                    .contains = contains,
                    .save = save,
                    .remove = remove,
                };

                pub fn store(self: *VersionedKeychainStore) CredentialStore {
                    return .{ .context = self, .vtable = &vtable };
                }

                fn load(context: *anyopaque, account: *const AccountKey, kind: CredentialKind, out: *Credential) LoadError!void {
                    const self: *VersionedKeychainStore = @ptrCast(@alignCast(context));
                    self.primary.load(account, kind, out) catch |err| switch (err) {
                        error.NotFound => return self.legacy.load(account, kind, out),
                        else => return err,
                    };
                }

                fn contains(context: *anyopaque, account: *const AccountKey, kind: CredentialKind) LoadError!bool {
                    const self: *VersionedKeychainStore = @ptrCast(@alignCast(context));
                    if (try self.primary.contains(account, kind)) return true;
                    return self.legacy.contains(account, kind);
                }

                fn save(context: *anyopaque, account: *const AccountKey, kind: CredentialKind, credential: *const Credential) SaveError!void {
                    const self: *VersionedKeychainStore = @ptrCast(@alignCast(context));
                    return self.primary.save(account, kind, credential);
                }

                fn remove(context: *anyopaque, account: *const AccountKey, kind: CredentialKind) RemoveError!void {
                    const self: *VersionedKeychainStore = @ptrCast(@alignCast(context));

                    return self.primary.remove(account, kind);
                }
            };

            const sec = struct {
                const CFTypeRef = ?*const anyopaque;
                const CFStringRef = ?*const anyopaque;
                const CFDataRef = ?*const anyopaque;
                const CFDictionaryRef = ?*const anyopaque;
                const CFAllocatorRef = ?*const anyopaque;
                const CFIndex = isize;
                const CFTypeID = usize;
                const Boolean = u8;

                const encoding_utf8: u32 = 0x0800_0100;

                extern const kCFAllocatorDefault: CFAllocatorRef;
                extern const kCFBooleanTrue: CFTypeRef;
                extern const kCFBooleanFalse: CFTypeRef;
                extern const kCFTypeDictionaryKeyCallBacks: anyopaque;
                extern const kCFTypeDictionaryValueCallBacks: anyopaque;

                extern fn CFStringCreateWithBytes(
                    alloc: CFAllocatorRef,
                    bytes: [*]const u8,
                    num_bytes: CFIndex,
                    encoding: u32,
                    is_external_representation: Boolean,
                ) CFStringRef;
                extern fn CFDataCreate(alloc: CFAllocatorRef, bytes: [*]const u8, length: CFIndex) CFDataRef;
                extern fn CFDataGetLength(data: CFDataRef) CFIndex;
                extern fn CFDataGetBytePtr(data: CFDataRef) ?[*]const u8;
                extern fn CFDataGetTypeID() CFTypeID;
                extern fn CFGetTypeID(cf: CFTypeRef) CFTypeID;
                extern fn CFDictionaryCreate(
                    alloc: CFAllocatorRef,
                    keys: [*]const ?*const anyopaque,
                    values: [*]const ?*const anyopaque,
                    num_values: CFIndex,
                    key_callbacks: ?*const anyopaque,
                    value_callbacks: ?*const anyopaque,
                ) CFDictionaryRef;
                extern fn CFRelease(cf: CFTypeRef) void;

                extern const kSecClass: CFStringRef;
                extern const kSecClassGenericPassword: CFStringRef;
                extern const kSecAttrService: CFStringRef;
                extern const kSecAttrAccount: CFStringRef;
                extern const kSecAttrAccessible: CFStringRef;
                extern const kSecAttrAccessibleWhenUnlockedThisDeviceOnly: CFStringRef;
                extern const kSecAttrSynchronizable: CFStringRef;
                extern const kSecAttrAccess: CFStringRef;
                extern const kSecValueData: CFStringRef;
                extern const kSecReturnData: CFStringRef;
                extern const kSecMatchLimit: CFStringRef;
                extern const kSecMatchLimitOne: CFStringRef;
                extern const kSecUseAuthenticationUI: CFStringRef;
                extern const kSecUseAuthenticationUIAllow: CFStringRef;
                extern const kSecUseAuthenticationUIFail: CFStringRef;

                extern fn SecItemCopyMatching(query: CFDictionaryRef, result: ?*CFTypeRef) OSStatus;
                extern fn SecItemAdd(attributes: CFDictionaryRef, result: ?*CFTypeRef) OSStatus;
                extern fn SecItemUpdate(query: CFDictionaryRef, attributes_to_update: CFDictionaryRef) OSStatus;
                extern fn SecItemDelete(query: CFDictionaryRef) OSStatus;
                extern fn SecAccessCreate(descriptor: CFStringRef, trusted_list: CFTypeRef, access: *CFTypeRef) OSStatus;
                extern fn SecCodeCopySelf(flags: u32, code: *CFTypeRef) OSStatus;
                extern fn SecRequirementCreateWithString(text: CFStringRef, flags: u32, requirement: *CFTypeRef) OSStatus;
                extern fn SecCodeCheckValidity(code: CFTypeRef, flags: u32, requirement: CFTypeRef) OSStatus;

                const max_entries: usize = 7;

                const Dictionary = struct {
                    keys: [max_entries]?*const anyopaque = @splat(null),
                    values: [max_entries]?*const anyopaque = @splat(null),
                    len: usize = 0,

                    fn put(self: *Dictionary, key: CFStringRef, value: CFTypeRef) void {
                        std.debug.assert(self.len < max_entries);
                        self.keys[self.len] = key;
                        self.values[self.len] = value;
                        self.len += 1;
                    }

                    fn create(self: *const Dictionary) CFDictionaryRef {
                        return CFDictionaryCreate(
                            kCFAllocatorDefault,
                            &self.keys,
                            &self.values,
                            @intCast(self.len),
                            &kCFTypeDictionaryKeyCallBacks,
                            &kCFTypeDictionaryValueCallBacks,
                        );
                    }
                };

                const Identity = struct {
                    service: CFStringRef,
                    account: CFStringRef,

                    fn init(query: ItemQuery) ?Identity {
                        if (query.service.len == 0 or query.account.len == 0) return null;
                        const service = CFStringCreateWithBytes(
                            kCFAllocatorDefault,
                            query.service.ptr,
                            @intCast(query.service.len),
                            encoding_utf8,
                            0,
                        ) orelse return null;
                        const account = CFStringCreateWithBytes(
                            kCFAllocatorDefault,
                            query.account.ptr,
                            @intCast(query.account.len),
                            encoding_utf8,
                            0,
                        ) orelse {
                            CFRelease(service);
                            return null;
                        };
                        return .{ .service = service, .account = account };
                    }

                    fn deinit(self: Identity) void {
                        CFRelease(self.service);
                        CFRelease(self.account);
                    }

                    fn lookup(self: Identity) Dictionary {
                        var dictionary: Dictionary = .{};
                        dictionary.put(kSecClass, kSecClassGenericPassword);
                        dictionary.put(kSecAttrService, self.service);
                        dictionary.put(kSecAttrAccount, self.account);
                        dictionary.put(kSecAttrSynchronizable, kCFBooleanFalse);
                        return dictionary;
                    }
                };

                fn putAuthenticationUI(dictionary: *Dictionary, policy: AuthenticationUI) void {
                    dictionary.put(
                        kSecUseAuthenticationUI,
                        if (policy == .allow) kSecUseAuthenticationUIAllow else kSecUseAuthenticationUIFail,
                    );
                }

                fn createData(credential: *const Credential, staging: []u8) CFDataRef {
                    const plaintext = credential.copyPlaintext(staging) catch return null;

                    const bytes: [*]const u8 = if (plaintext.len == 0) staging.ptr else plaintext.ptr;
                    return CFDataCreate(kCFAllocatorDefault, bytes, @intCast(plaintext.len));
                }

                fn stableSignerValid() bool {
                    const requirement_text = CFStringCreateWithBytes(
                        kCFAllocatorDefault,
                        stable_designated_requirement.ptr,
                        @intCast(stable_designated_requirement.len),
                        encoding_utf8,
                        0,
                    ) orelse return false;
                    defer CFRelease(requirement_text);
                    var requirement: CFTypeRef = null;
                    if (SecRequirementCreateWithString(requirement_text, 0, &requirement) != status_success) return false;
                    defer CFRelease(requirement);
                    var code: CFTypeRef = null;
                    if (SecCodeCopySelf(0, &code) != status_success) return false;
                    defer CFRelease(code);
                    return SecCodeCheckValidity(code, 0, requirement) == status_success;
                }
            };

            var system_context: u8 = 0;

            const system_vtable: SecItemApi.VTable = .{
                .copy = systemCopy,
                .matches = systemMatches,
                .add = systemAdd,
                .update = systemUpdate,
                .delete = systemDelete,
            };

            pub fn systemSecItemApi() SecItemApi {
                return .{ .context = &system_context, .vtable = &system_vtable };
            }

            fn systemCopy(_: *anyopaque, query: ItemQuery, out: *Credential) OSStatus {
                if (!query.isSelfOwned()) return status_param;
                return permittedSystemCopy(query, out);
            }

            fn permittedSystemCopy(query: ItemQuery, out: *Credential) OSStatus {
                const identity = sec.Identity.init(query) orelse return status_allocate;
                defer identity.deinit();

                var dictionary = identity.lookup();
                sec.putAuthenticationUI(&dictionary, query.authentication_ui);
                dictionary.put(sec.kSecReturnData, sec.kCFBooleanTrue);
                dictionary.put(sec.kSecMatchLimit, sec.kSecMatchLimitOne);
                const request = dictionary.create() orelse return status_allocate;
                defer sec.CFRelease(request);

                var result: sec.CFTypeRef = null;
                const status = sec.SecItemCopyMatching(request, &result);
                if (status != status_success) return status;
                const data = result orelse return status_decode;
                defer sec.CFRelease(data);

                if (sec.CFGetTypeID(data) != sec.CFDataGetTypeID()) return status_decode;

                const length = sec.CFDataGetLength(data);
                if (length < 0) return status_decode;
                if (length > max_credential_bytes) return status_data_too_large;
                const bytes = sec.CFDataGetBytePtr(data) orelse return status_decode;

                out.reset();
                out.append(bytes[0..@intCast(length)]) catch return status_data_too_large;
                return status_success;
            }

            fn systemMatches(_: *anyopaque, query: ItemQuery) OSStatus {
                if (!query.isSelfOwned()) return status_param;
                return permittedSystemMatches(query);
            }

            fn permittedSystemMatches(query: ItemQuery) OSStatus {
                const identity = sec.Identity.init(query) orelse return status_allocate;
                defer identity.deinit();

                var dictionary = identity.lookup();
                sec.putAuthenticationUI(&dictionary, query.authentication_ui);
                dictionary.put(sec.kSecMatchLimit, sec.kSecMatchLimitOne);
                const request = dictionary.create() orelse return status_allocate;
                defer sec.CFRelease(request);

                return sec.SecItemCopyMatching(request, null);
            }

            fn systemAdd(_: *anyopaque, query: ItemQuery, credential: *const Credential) OSStatus {
                if (!query.isSelfOwned()) return status_param;
                return permittedSystemAdd(query, credential);
            }

            fn permittedSystemAdd(query: ItemQuery, credential: *const Credential) OSStatus {
                if (query.isSelfOwned() and !query.isWritableV2()) return status_param;
                const identity = sec.Identity.init(query) orelse return status_allocate;
                defer identity.deinit();

                var staging: [max_credential_bytes]u8 = undefined;
                defer std.crypto.secureZero(u8, &staging);
                const data = sec.createData(credential, &staging) orelse return status_allocate;
                defer sec.CFRelease(data);

                var access: sec.CFTypeRef = null;
                if (query.isWritableV2()) {
                    const access_status = sec.SecAccessCreate(identity.account, null, &access);
                    if (access_status != status_success) return access_status;
                }
                defer if (access != null) sec.CFRelease(access);

                var dictionary = identity.lookup();
                sec.putAuthenticationUI(&dictionary, query.authentication_ui);
                if (access != null) dictionary.put(sec.kSecAttrAccess, access);
                dictionary.put(sec.kSecValueData, data);
                const attributes = dictionary.create() orelse return status_allocate;
                defer sec.CFRelease(attributes);

                return sec.SecItemAdd(attributes, null);
            }

            fn systemUpdate(_: *anyopaque, query: ItemQuery, credential: *const Credential) OSStatus {
                if (!query.isWritableV2()) return status_param;
                return permittedSystemUpdate(query, credential);
            }

            fn permittedSystemUpdate(query: ItemQuery, credential: *const Credential) OSStatus {
                const identity = sec.Identity.init(query) orelse return status_allocate;
                defer identity.deinit();

                var lookup = identity.lookup();
                sec.putAuthenticationUI(&lookup, query.authentication_ui);
                const request = lookup.create() orelse return status_allocate;
                defer sec.CFRelease(request);

                var staging: [max_credential_bytes]u8 = undefined;
                defer std.crypto.secureZero(u8, &staging);
                const data = sec.createData(credential, &staging) orelse return status_allocate;
                defer sec.CFRelease(data);

                var changes: sec.Dictionary = .{};
                changes.put(sec.kSecValueData, data);
                const update = changes.create() orelse return status_allocate;
                defer sec.CFRelease(update);

                return sec.SecItemUpdate(request, update);
            }

            fn systemDelete(_: *anyopaque, query: ItemQuery) OSStatus {
                if (!query.isWritableV2()) return status_param;
                return permittedSystemDelete(query);
            }

            fn permittedSystemDelete(query: ItemQuery) OSStatus {
                const identity = sec.Identity.init(query) orelse return status_allocate;
                defer identity.deinit();

                var lookup = identity.lookup();
                sec.putAuthenticationUI(&lookup, query.authentication_ui);
                const request = lookup.create() orelse return status_allocate;
                defer sec.CFRelease(request);

                return sec.SecItemDelete(request);
            }

            pub const SystemKeychain = struct {
                backend: SecItemStore,
                primary_adapter: KeychainStore,
                legacy_adapter: KeychainStore,
                sign_in_adapter: KeychainStore,
                versioned: VersionedKeychainStore = undefined,

                pub fn init(service: []const u8) error{ ForeignKeychainService, UntrustedBuild }!SystemKeychain {
                    if (!std.mem.eql(u8, service, v2_service)) return error.ForeignKeychainService;

                    if (!sec.stableSignerValid()) return error.UntrustedBuild;
                    return .{
                        .backend = .init(systemSecItemApi()),
                        .primary_adapter = try KeychainStore.init(v2_service),
                        .legacy_adapter = try KeychainStore.init(legacy_service),
                        .sign_in_adapter = try KeychainStore.initForSignIn(v2_service),
                    };
                }

                pub fn store(self: *SystemKeychain) CredentialStore {
                    const wired = self.backend.backend();
                    self.primary_adapter.backend = wired;
                    self.legacy_adapter.backend = wired;
                    self.sign_in_adapter.backend = wired;
                    self.versioned = .{
                        .primary = self.primary_adapter.store(),
                        .legacy = self.legacy_adapter.store(),
                    };
                    return self.versioned.store();
                }

                pub fn signInStore(self: *SystemKeychain) CredentialStore {
                    self.sign_in_adapter.backend = self.backend.backend();
                    return self.sign_in_adapter.store();
                }
            };
        };
    };
}
