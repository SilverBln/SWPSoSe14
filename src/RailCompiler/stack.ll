@stack = global [1000 x i8*] undef ; stack containing pointers to i8
@sp = global i64 0 ; global stack pointer (or rather: current number of elements)


; Constants
@true = global [2 x i8] c"1\00"
@false = global [2 x i8] c"0\00"
@printf_str_fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@err_stack_underflow = private unnamed_addr constant [18 x i8] c"Stack underflow!\0A\00"


; External declarations
declare signext i32 @atol(i8*)
declare signext i32 @snprintf(i8*, i16 zeroext, ...)
declare signext i32 @printf(i8*, ...)
declare i8* @malloc(i16 zeroext) ; void *malloc(size_t) and size_t is 16 bits long (SIZE_MAX)
declare void @exit(i32 signext)


; Debugging stuff
@to_str  = private unnamed_addr constant [3 x i8] c"%i\00"
@pushing = private unnamed_addr constant [14 x i8] c"Pushing [%s]\0A\00"
@popped  = private unnamed_addr constant [13 x i8] c"Popped [%s]\0a\00"

@before_casting  = private unnamed_addr constant [17 x i8] c"Before casting \0A\00"
@after_casting  = private unnamed_addr constant [18 x i8] c"After casting %i\0A\00"


; Function definitions

; Get number of element on the stack
define i64 @stack_get_size() {
  %sp = load i64* @sp
  ret i64 %sp
}

; Push the stack size onto the stack
define void @underflow_check() {
  %stack_size = call i64 @stack_get_size()
  call void @push_int(i64 %stack_size)
  ret void
}

; Exit the program if stack is empty
define void @underflow_assert() {
  %stack_size = call i64 @stack_get_size()
  %stack_empty = icmp eq i64 %stack_size, 0
  br i1 %stack_empty, label %uas_crash, label %uas_okay

uas_crash:
  %err = getelementptr [18 x i8]* @err_stack_underflow, i8 0, i8 0
  call i32(i8*, ...)* @printf(i8* %err)
  call void @exit(i32 1)

  ret void

uas_okay:
  ret void
}

; Pop stack and print result string
define void @print() {
  ; TODO: Check if the top stack element is a string and crash if it is not.
  call void @underflow_assert()

  %fmt = getelementptr [3 x i8]* @printf_str_fmt, i8 0, i8 0
  %val = call i8* @pop()
  call i32(i8*, ...)* @printf(i8* %fmt, i8* %val)

  ret void
}

; Pop stack, print result string and exit the program.
define void @crash() {
  ; print() will check if there is anything to pop()
  ; and if there is not, it will crash the program.
  call void @print()
  call void @exit(i32 1)

  ret void
}

define void @push(i8* %str_ptr) {
  ; dereferencing @sp by loading value into memory
  %sp   = load i64* @sp

  ; get position on the stack, the stack pointer points to. this is the top of
  ; the stack.
  ; nice getelementptr FAQ: http://llvm.org/docs/GetElementPtr.html
  ;                     value of pointer type,  index,    field
  %top = getelementptr [1000 x i8*]* @stack,   i8 0,     i64 %sp

  ; the contents of memory are updated to contain %str_ptr at the location
  ; specified by the %addr operand
  store i8* %str_ptr, i8** %top

  ; increase stack pointer to point to new free, top of stack
  %newsp = add i64 %sp, 1
  store i64 %newsp, i64* @sp

  ret void
}

; pops element from stack and converts in integer
; returns the element, in case of error undefined
define i64 @pop_int(){
  ; pop
  %top = call i8* @pop()

  ; convert to int, check for error
  %top_int0 = call i32 @atol(i8* %top)
  %top_int1 = sext i32 %top_int0 to i64

  ; return
  ret i64 %top_int1
}

define void @push_int(i64 %top_int)
{
  ; allocate memory to store string in
  ; TODO: Make sure this is free()'d at _some_ point during
  ;       program execution.
  %buffer_addr = call i8* @malloc(i16 128)
  %to_str_ptr = getelementptr [3 x i8]* @to_str, i64 0, i64 0

  ; convert to string
  call i32(i8*, i16, ...)* @snprintf(
          i8* %buffer_addr, i16 128, i8* %to_str_ptr, i64 %top_int)

  ; push on stack
  call void(i8*)* @push(i8* %buffer_addr)

  ret void
}

define void @add_int() {
  ; get top of stack
  %top_1   = call i64()* @pop_int()

  ; get second top of stack
  %top_2   = call i64()* @pop_int()

  ; add the two values
  %res = add i64 %top_1, %top_2

  ; store result on stack
  call void(i64)* @push_int(i64 %res)

  ret void
}

define void @sub_int() {
  ; get top of stack
  %top_1   = call i64()* @pop_int()

  ; get second top of stack
  %top_2   = call i64()* @pop_int()

  ; sub the two values
  %res = sub i64 %top_1, %top_2

  ; store result on stack
  call void(i64)* @push_int(i64 %res)

  ret void
}

define i8* @peek() {
  %sp   = load i64* @sp
  %top_of_stack = sub i64 %sp, 1
  %addr = getelementptr [1000 x i8*]* @stack, i8 0, i64 %top_of_stack
  %val = load i8** %addr
  ret i8* %val
}

define i8* @pop() {
  %val = call i8*()* @peek()
  %sp = load i64* @sp
  %top_of_stack = sub i64 %sp, 1
  store i64 %top_of_stack, i64* @sp
  ret i8* %val
}

; UNTESTED
define void @strlen() {
entry:
  %str = call i8*()* @pop()
  br label %loop
loop:
  %i = phi i64 [1, %entry ], [ %next_i, %loop ]
  %next_i = add i64 %i, 1
  %addr = getelementptr i8* %str, i64 %i
  %c = load i8* %addr
  %cond = icmp eq i8 %c, 0
  br i1 %cond, label %finished, label %loop
finished:
  call void(i64)* @push_int(i64 %i)
  ret void
}

; UNTESTED
define void @streq() {
entry:
  %str1 = call i8*()* @pop()
  %str2 = call i8*()* @pop()
  br label %loop
loop:
  %i = phi i64 [ 1, %entry ], [ %next_i, %cont ]
  %addr1 = getelementptr i8* %str1, i64 %i
  %addr2 = getelementptr i8* %str2, i64 %i
  %c1 = load i8* %addr1
  %c2 = load i8* %addr2
  %cond = icmp eq i8 %c1, %c2
  br i1 %cond, label %cont, label %fail
cont:
  %next_i = add i64 %i, 1
  %cond2 = icmp eq i8 %c1, 0
  br i1 %cond2, label %success, label %loop
success:
  %t = getelementptr [2 x i8]* @true, i64 0, i64 0
  call void(i8*)* @push(i8* %t)
  ret void
fail:
  %f = getelementptr [2 x i8]* @true, i64 0, i64 0
  call void(i8*)* @push(i8* %f)
  ret void
}


@number0 = private unnamed_addr constant [2 x i8] c"5\00"
@number1  = private unnamed_addr constant [2 x i8] c"2\00"

define i32 @main_() {
 %pushingptr = getelementptr [14 x i8]* @pushing, i64 0, i64 0
 %poppedptr = getelementptr [13 x i8]* @popped, i64 0, i64 0

 ; push two numbers on the stack
 %number0 = getelementptr [2 x i8]* @number0, i64 0, i64 0
 %number1 = getelementptr [2 x i8]* @number1, i64 0, i64 0

 call i32(i8*, ...)* @printf(i8* %pushingptr, i8* %number0)
 call void(i8*)* @push(i8* %number0)

 call i32(i8*, ...)* @printf(i8* %pushingptr, i8* %number1)
 call void(i8*)* @push(i8* %number1)

 call void @underflow_check()
 %size0 = call i8*()* @pop()
 call i32(i8*, ...)* @printf(i8* %poppedptr, i8* %size0)

 call void @sub_int()
 %sum  = call i8*()* @pop()
 call i32(i8*, ...)* @printf(i8* %poppedptr, i8* %sum)

 call void @underflow_check()
 %size1 = call i8*()* @pop()
 call i32(i8*, ...)* @printf(i8* %poppedptr, i8* %size1)

 ret i32 0
}

; vim:sw=2 ts=2 et