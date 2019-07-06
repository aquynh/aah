//
//  objc-cif.m
//  aah
//
//  Created by Jesús A. Álvarez on 06/05/2019.
//  Copyright © 2019 namedfork. All rights reserved.
//

#import "aah.h"
#import <objc/runtime.h>

static void cif_cache_add_methods(Class cls, bool only_emulated) {
    unsigned int methodCount;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int i = 0; i < methodCount; i++) {
        Method m = methods[i];
        IMP imp = method_getImplementation(m);
        if (only_emulated) {
            Dl_info info;
            if (dladdr(imp, &info) && !should_emulate_image(info.dli_fbase)) {
                continue;
            }
        }
        const char *typeEncoding = method_getTypeEncoding(m);
        if (strlen(typeEncoding) > 0 && strchr(typeEncoding, '<') == 0 && strchr(typeEncoding, ',') == 0) {
            char *name = NULL;
            asprintf(&name, "%c[%s %s]", class_isMetaClass(cls) ? '+' : '-', class_getName(cls), sel_getName(method_getName(m)));
            cif_cache_add(imp, typeEncoding, name);
        }
    }
}

hidden void cif_cache_add_class(const char *name) {
    cif_cache_add_methods(objc_getClass(name), false);
    cif_cache_add_methods(objc_getMetaClass(name), false);
}

struct method {
    const char *name;
    const char *types;
    void *implementation;
};

struct method_list {
    uint32_t entrySize;
    uint32_t count;
    struct method methods[];
};

struct class_info {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
    uint32_t reserved;
    const uint8_t * ivarLayout;
    const char * name;
    struct method_list * baseMethodList;
    void * baseProtocols; // protocol_list_t
    const void * ivars; // ivar_list_t
    const uint8_t * weakIvarLayout;
    void * baseProperties; // property_list_t
};

struct classref {
    uint64_t isa;
    uint64_t superclass;
    uint64_t cache;
    uint64_t vtable;
    struct class_info *data;
};

struct cat_info {
    const char *name;
    void *cls;
    struct method_list *instanceMethods;
    struct method_list *classMethods;
    void *protocols;
    void *instanceProperties;
};

#define RO_META 1

hidden void load_objc_methods(struct method_list *methods, bool meta, const char *name) {
    if (methods == NULL) {
        return;
    }
    for(uint32_t i = 0; i < methods->count; i++) {
        struct method * method = &methods->methods[i];
        char *method_name = NULL;
        asprintf(&method_name, "%c[%s %s]", meta ? '+' : '-', name, method->name);
        printf("%s (%s) -> %p\n", method_name, method->types, method->implementation);
        cif_cache_add(method->implementation, method->types, method_name);
    }
}

hidden void load_objc_entrypoints(const struct mach_header_64 *mh, intptr_t vmaddr_slide) {
    // FIXME: must vmaddr_slide really be applied?
    
    // load classes
    const struct section_64 *classlist = getsectbynamefromheader_64(mh, "__DATA", "__objc_classlist");
    if (classlist) {
        uint64_t numClasses = classlist->size / 8;
        struct classref **classes = (struct classref**)(classlist->addr + vmaddr_slide);
        for(uint64_t i = 0; i < numClasses; i++) {
            struct classref *class = classes[i];
            bool is_metaclass = class->data->flags & RO_META;
            load_objc_methods(class->data->baseMethodList, is_metaclass, class->data->name);
        }
    }
    
    // load categories
    const struct section_64 *catlist = getsectbynamefromheader_64(mh, "__DATA", "__objc_catlist");
    if (catlist) { // meow
        uint64_t numCats = catlist->size / 8;
        struct cat_info **cats = (struct cat_info**)(catlist->addr + vmaddr_slide);
        for(uint64_t i = 0; i < numCats; i++) {
            struct cat_info *cat = cats[i];
            load_objc_methods(cat->classMethods, true, cat->name);
            load_objc_methods(cat->instanceMethods, false, cat->name);
        }
    }
}
