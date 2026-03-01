#!/bin/bash
# Script for testing variable types

# String
str_var="hello world"

# Integer
declare -i int_var=42

# Array
declare -a arr_var=("apple" "banana" "cherry")

# Associative array
declare -A assoc_var=([name]="John" [age]="30" [city]="NYC")

# Readonly
declare -r readonly_var="constant"

# Exported
export exported_var="visible"

# Nameref (bash 4.3+)
target="referenced"
declare -n ref_var=target

echo "$str_var $int_var ${arr_var[0]} ${assoc_var[name]} $readonly_var $exported_var $ref_var"
