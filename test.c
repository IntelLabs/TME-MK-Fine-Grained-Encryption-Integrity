#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <assert.h>
#include <malloc.h>

#define CLSIZE 64
#define CLMASK (uintptr_t)(CLSIZE-1)

uint64_t kPtrTagMask = 0x00003f0000000000uLL;
uint64_t kPtrTagShift = 40;
#define _read8_q(ptr)  ({ volatile uint64_t __result = 0xDEAD; __result = (*(volatile uint64_t*)(ptr)); __result; })
#define _write_q(ptr, value) do { (*(volatile uint64_t*)(ptr)) = (uint64_t)(value); } while(0)
#define _is_tagged(ptr) ((uint64_t)(ptr) & kPtrTagMask)
#define _is_aligned(ptr) (((uintptr_t)(p) & CLMASK) == 0)
#define _check_access(ptr) do { \
	if((uintptr_t)ptr != 0 && (uintptr_t)ptr != -1ULL) {\
		uint64_t _expected = 0xFF00000000000000ULL | (uint64_t)ptr; \
		volatile uint64_t _result = 0; \
		volatile uint64_t _previous = _read8_q(ptr); \
		_write_q(ptr, _expected); \
		_result = _read8_q(ptr); \
		assert(_result == _expected); \
		_write_q(ptr, _previous); \
	} \
	} while(0)

void* check(void * p){
	printf("p = %13p  ", p);

	assert(_is_aligned(p));
	printf("[OK] aligned. ");

	assert(_is_tagged(p));
	printf("[OK] tagged. ");

	_check_access(p);
	printf("[OK] access. ");

	printf("\n");
	return p;
}

int main(){
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);

	size_t size = 8;
	void* p  = NULL;
	void* q  = NULL;

	printf("\n");

	p = check(malloc(  1)); free(p);
	p = check(malloc( 64)); free(p);
	p = check(malloc(128));
	p = check(malloc(128)); free(p);

	p = check(malloc(64));
	q = check(malloc(64));
	printf("access within bounds:  %p: ", p);
	_check_access(p);
	printf("[OK]\n");

	void* p_oob  = p + 64;
	printf("access outside bounds: %p  (expecting crash): \n", p_oob);
	_check_access(p_oob);

	printf("unreachable\n");
	assert(0);

	return 0;
}
