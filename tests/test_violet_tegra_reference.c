// Cross-check the real Tegra GOB block-linear importer against the independently
// specified BNTX x/y address formula. Synthetic textures only; no game assets.
// Stress odd widths, partial GOBs, compressed 16-byte blocks and mip heights.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../runtime/nvn/tegra.h"

static uint64_t reference_offset(unsigned x, unsigned y, unsigned width, unsigned bpp, unsigned bh) {
    uint64_t gobs = ((uint64_t)width * bpp + 63u) / 64u;
    uint64_t xb = (uint64_t)x * bpp;
    uint64_t gob = (y / (8u * bh)) * (512u * bh * gobs)
                 + (xb / 64u) * (512u * bh)
                 + ((y % (8u * bh)) / 8u) * 512u;
    return gob + ((xb % 64u) / 32u) * 256u
               + ((y % 8u) / 2u) * 64u
               + ((xb % 32u) / 16u) * 32u
               + (y % 2u) * 16u + xb % 16u;
}

int main(void) {
    const unsigned widths[] = {1,2,3,4,5,7,8,9,15,16,17,31,32,33,63,64,65,127,128,129};
    const unsigned heights[] = {1,2,3,7,8,9,15,16,17,31,32,33,63,64,65};
    const unsigned bpps[] = {1,2,4,8,16};
    unsigned cases=0;
    for(unsigned bi=0;bi<sizeof bpps/sizeof *bpps;bi++)
    for(unsigned wi=0;wi<sizeof widths/sizeof *widths;wi++)
    for(unsigned hi=0;hi<sizeof heights/sizeof *heights;hi++)
    for(unsigned bhlog=0;bhlog<=4;bhlog++){
        unsigned w=widths[wi],h=heights[hi],bpp=bpps[bi],bh=1u<<bhlog;
        unsigned gobs=(w*bpp+63u)/64u;
        uint64_t packed_size=(uint64_t)gobs*512u*bh*((h+8u*bh-1u)/(8u*bh));
        size_t linear_size=(size_t)w*h*bpp;
        uint8_t *linear=malloc(linear_size), *packed=calloc(1,(size_t)packed_size), *got=malloc(linear_size);
        if(!linear||!packed||!got)return 2;
        for(size_t i=0;i<linear_size;i++)linear[i]=(uint8_t)(i*73u+(i>>3)*19u+11u);
        tegra_swizzle(linear,packed,w,h,1,bpp,bhlog,0);
        for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++){
            uint64_t at=reference_offset(x,y,w,bpp,bh);
            if(at+bpp>packed_size||memcmp(packed+at,linear+((size_t)y*w+x)*bpp,bpp)){
                fprintf(stderr,"Mismatch: %ux%u bpp=%u block-height=%u at (%u,%u) offset=%llu\n",
                        w,h,bpp,bh,x,y,(unsigned long long)at);
                return 1;
            }
        }
        tegra_deswizzle(packed,got,w,h,1,bpp,bhlog,0);
        if(memcmp(linear,got,linear_size)){
            fprintf(stderr,"Deswizzle mismatch: %ux%u bpp=%u block-height=%u\n",w,h,bpp,bh);
            return 1;
        }
        free(linear);free(packed);free(got);cases++;
    }
    printf("PASS: %u Tegra GOB reference and roundtrip cases\n",cases);
    return 0;
}
