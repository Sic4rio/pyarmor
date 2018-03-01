source test-header.sh

# ======================================================================
#
# Initial setup.
#
# ======================================================================

PYARMOR="${PYTHON} pyarmor2.py"

csih_inform "Python is $PYTHON"
csih_inform "Tested Package: $pkgfile"
csih_inform "Pyarmor is $PYARMOR"

csih_inform "Make workpath ${workpath}"
rm -rf ${workpath}
mkdir -p ${workpath} || csih_error "Make workpath FAILED"

cd ${workpath}
[[ ${pkgfile} == *.zip ]] && unzip ${pkgfile} > /dev/null 2>&1
[[ ${pkgfile} == *.tar.bz2 ]] && tar xjf ${pkgfile}
cd pyarmor-$version || csih_error "Invalid pyarmor package file"
# From pyarmor 3.5.1, main scripts are moved to src
[[ -d src ]] && mv src/* ./

csih_inform "Prepare for system testing"
echo ""


# ======================================================================
#
#  Bootstrap: help and version
#
# ======================================================================

echo ""
echo "-------------------- Bootstrap ---------------------------------"
echo ""

csih_inform "Case 0.1: show help and import pytransform"
$PYARMOR --help >result.log 2>&1 || csih_bug "Case 1.1 FAILED"
[[ -f _pytransform$DLLEXT ]] || csih_error "no pytransform extension found"

csih_inform "Case 0.2: show version information"
$PYARMOR --version >result.log 2>&1 || csih_bug "show version FAILED"

echo ""
echo "-------------------- Bootstrap End -----------------------------"
echo ""

# ======================================================================
#
#  Command: obfuscate
#
# ======================================================================

echo ""
echo "-------------------- Test Command obfuscate --------------------"
echo ""

csih_inform "Case 1.1: obfuscate script"
$PYARMOR obfuscate --src examples/simple --entry queens.py --output dist \
                   "*.py"  >result.log 2>&1

check_file_exists dist/queens.py
check_file_content dist/queens.py '__pyarmor__(__name__'

( cd dist; $PYTHON queens.py >result.log 2>&1 )
check_file_content dist/result.log 'Found 92 solutions'

echo ""
echo "-------------------- Test Command obfuscate END ----------------"
echo ""


# ======================================================================
#
#  Command: init
#
# ======================================================================

echo ""
echo "-------------------- Test Command init -------------------------"
echo ""

csih_inform "Case 2.1: init pybench"
$PYARMOR init --src examples/pybench --entry pybench.py \
              projects/pybench >result.log 2>&1

check_file_exists projects/pybench/.pyarmor_config
check_file_exists projects/pybench/.pyarmor_capsule.zip

csih_inform "Case 2.1: init py2exe"
$PYARMOR init --src examples/py2exe --entry "hello.py,setup.py" \
              projects/py2exe >result.log 2>&1

check_file_exists projects/py2exe/.pyarmor_config
check_file_exists projects/py2exe/.pyarmor_capsule.zip

csih_inform "Case 2.2: init clone py2exe"
$PYARMOR init --src examples/py2exe2 --clone projects/py2exe \
              projects/py2exe-clone >result.log 2>&1

check_return_value
check_file_exists projects/py2exe-clone/.pyarmor_config
check_file_exists projects/py2exe-clone/.pyarmor_capsule.zip

echo ""
echo "-------------------- Test Command init END ---------------------"
echo ""

# ======================================================================
#
#  Command: config
#
# ======================================================================

echo ""
echo "-------------------- Test Command config -----------------------"
echo ""

csih_inform "Case 3.1: config py2exe"
( cd projects/py2exe; $ARMOR config --runtime-path='' \
    --manifest="global-include *.py, exclude __manifest__.py" \
    >result.log 2>&1 )
check_return_value

echo ""
echo "-------------------- Test Command config END -------------------"
echo ""

# ======================================================================
#
#  Command: info
#
# ======================================================================

echo ""
echo "-------------------- Test Command info -------------------------"
echo ""

csih_inform "Case 4.1: info pybench"
( cd projects/pybench; $ARMOR info >result.log 2>&1 )
check_return_value

csih_inform "Case 4.2: info py2exe"
( cd projects/py2exe; $ARMOR info >result.log 2>&1 )
check_return_value

echo ""
echo "-------------------- Test Command info END ---------------------"
echo ""

# ======================================================================
#
#  Command: check
#
# ======================================================================

echo ""
echo "-------------------- Test Command check ------------------------"
echo ""

csih_inform "Case 5.1: check pybench"
( cd projects/pybench; $ARMOR check >result.log 2>&1 )
check_return_value

csih_inform "Case 5.2: check py2exe"
( cd projects/py2exe; $ARMOR check >result.log 2>&1 )
check_return_value

echo ""
echo "-------------------- Test Command check END --------------------"
echo ""

# ======================================================================
#
#  Command: build
#
# ======================================================================

echo ""
echo "-------------------- Test Command build ------------------------"
echo ""

csih_inform "Case 6.1: build pybench"
( cd projects/pybench; $ARMOR build >result.log 2>&1 )

output=projects/pybench/dist
check_file_exists $output/pybench.py
check_file_content $output/pybench.py 'pyarmor_runtime()'
check_file_content $output/pybench.py '__pyarmor__(__name__'

echo ""
echo "-------------------- Test Command build END --------------------"
echo ""

# ======================================================================
#
#  Command: licenses
#
# ======================================================================

echo ""
echo "-------------------- Test Command licenses ---------------------"
echo ""

csih_inform "Case 7.1: Generate project licenses"
output=projects/pybench/licenses

( cd projects/pybench; $ARMOR licenses code1 code2 code3 \
                       >licenses-result.log 2>&1 )
check_file_exists $output/code1/license.lic
check_file_exists $output/code2/license.lic
check_file_exists $output/code3/license.lic
check_file_exists $output/code1/license.lic.txt

( cd projects/pybench; $ARMOR licenses \
                              --expired $(next_month) \
                              --bind-disk '${harddisk_sn}' \
                              --bind-ipv4 '${ifip_address}' \
                              --bind-mac '${ifmac_address}' \
                              customer-tom >licenses-result.log 2>&1 )
check_file_exists $output/customer-tom/license.lic
check_file_exists $output/customer-tom/license.lic.txt

echo ""
echo "-------------------- Test Command licenses END -----------------"
echo ""

# ======================================================================
#
#  Command: hdinfo
#
# ======================================================================

echo ""
echo "-------------------- Test Command hdinfo -----------------------"
echo ""

csih_inform "Case 8.1: show hardware info"
$PYARMOR hdinfo >result.log 2>&1
check_return_value

echo ""
echo "-------------------- Test Command hdinfo END -------------------"
echo ""

# ======================================================================
#
#  Command: benchmark
#
# ======================================================================

echo ""
echo "-------------------- Test Command benchmark --------------------"
echo ""

csih_inform "Case 9.1: run benchmark test"
for obf_module_mode in none des ; do
  csih_inform "obf_module_mode: $obf_module_mode"
  for obf_code_mode in none des fast ; do
    csih_inform "obf_code_mode: $obf_code_mode"
    logfile="result_${obf_module_mode}_${obf_code_mode}.log"
    $PYARMOR benchmark --obf-module-mode $obf_module_mode \
                       --obf-code-mode $obf_code_mode \
                       >$logfile 2>&1
    check_return_value
    csih_inform "Write benchmark test results to $logfile"
    check_file_content $logfile "run_ten_thousand_obfuscated_bytecode"
    rm -rf .benchtest
  done
done

echo ""
echo "-------------------- Test Command benchmark END ----------------"
echo ""

# ======================================================================
#
#  Use Cases
#
# ======================================================================

echo ""
echo "-------------------- Test Use Cases ----------------------------"
echo ""

csih_inform "Case T-1.1: obfuscate module with project"
$PYARMOR init --src=examples/py2exe --entry=hello.py \
              projects/testmod >result.log 2>&1
$PYARMOR config --manifest="include queens.py" --disable-restrict-mode=1 \
              projects/testmod >result.log 2>&1
(cd projects/testmod; $ARMOR build >result.log 2>&1)

check_file_exists projects/testmod/dist/hello.py
check_file_content projects/testmod/dist/hello.py 'pyarmor_runtime'

check_file_exists projects/testmod/dist/queens.py
check_file_content projects/testmod/dist/queens.py '__pyarmor__(__name__'

(cd projects/testmod/dist; $PYTHON hello.py >result.log 2>&1 )
check_file_content projects/testmod/dist/result.log 'Found 92 solutions'

echo ""
echo "-------------------- Test Use Cases END ------------------------"
echo ""


# ======================================================================
#
# Finished and cleanup.
#
# ======================================================================

# Return test root
cd ../..

echo "----------------------------------------------------------------"
echo ""
csih_inform "Test finished for ${PYTHON}"

(( ${_bug_counter} == 0 )) || csih_error "${_bug_counter} bugs found"
echo "" && \
csih_inform "Remove workpath ${workpath}" \
&& echo "" \
&& rm -rf ${workpath} \
&& csih_inform "Congratulations, there is no bug found"
