'''
This script is used to build obfuscated scripts to extensions

1. Obfuscate the script with --no-cross-protection and --restrict 0

    pyarmor obfuscate --no-cross-protection --restrict 0 foo.py

2. Build obfuscated script to extension

    python buildext.py dist/foo.py

Or convert the obfuscated script "dist/foo.py" to .c file first, then
build it by any c compiler, for example

    python buildext.py -c dist/foo.py
    gcc $(python-config --cflags) $(python-config --ldflags) \\
        -shared -o dist/foo$(python-config --extension-suffix) \\
        dist/foo.c
'''
import argparse
import glob
import logging
import os
import random
import sys

from distutils.core import setup, Extension


logger = logging.getLogger('buildext')

c_template = '''
#define PYARMOR_RUNTIME "pyarmor_runtime"

#define PY_SSIZE_T_CLEAN

#include "Python.h"

#ifndef Py_PYTHON_H
# error Python headers needed to compile C extensions
#endif

#if (PY_MAJOR_VERSION >= 3)
# define BUILD_FILENAME(name) PyUnicode_FromFormat("<frozen %U>", name)
# define PYARMOR_ARGUMENTS "OOy#i"
#else
# define BUILD_FILENAME(name) PyString_FromFormat("<frozen %s>", PyString_AsString(name))
# define PYARMOR_ARGUMENTS "OOz#i"
#endif

static unsigned char cipher_code[] = { CIPHER_CODE };

#if defined(PYARMOR_SUPER_MODE)

static PyObject *
import_pyarmor()
{
  PyObject *t = PyImport_ImportModule(PYTRANSFORM_NAME);
  if (!t)
    return NULL;

  PyObject *f = PyDict_GetItemString(PyModule_GetDict(t), PYARMOR_NAME);
  Py_DECREF(t);

  if (!f)
    PyErr_Format(PyExc_ImportError, "No '%s.%s' found", PYTRANSFORM_NAME, PYARMOR_NAME);

  return f;
}

#else

static PyObject *
import_pyarmor()
{
  PyObject *t = NULL;
  PyObject *b = PyEval_GetBuiltins();
  PyObject *f = PyDict_GetItemString(b, PYARMOR_NAME);

  if (!f) {
    t = PyImport_ImportModule(PYTRANSFORM_NAME);
    if (!t)
      return NULL;

    PyObject *runtime = PyDict_GetItemString(PyModule_GetDict(t), PYARMOR_RUNTIME);
    if (!runtime) {
      PyErr_Format(PyExc_ImportError, "No '%s.%s' found", PYTRANSFORM_NAME, PYARMOR_RUNTIME);
      goto fail;
    }

    if (!PyObject_CallFunctionObjArgs(runtime, NULL)) {
      goto fail;
    }

    f = PyDict_GetItemString(b, PYARMOR_NAME);
    if (!f) {
      PyErr_Format(PyExc_ImportError, "No builtin function '%s' found", PYARMOR_NAME);
      goto fail;
    }

  fail:
    Py_DECREF(t);
  }

  return f;
}

#endif

static PyObject *
run_pyarmor(PyObject *m, PyObject *f)
{
  PyObject *d = PyModule_GetDict(m);
  PyObject *name = PyDict_GetItemString(d, "__name__");
  if (!name) {
    PyErr_SetString(PyExc_ImportError, "No module attribute '__name__' found");
    return NULL;
  }

  PyObject *file = PyDict_GetItemString(d, "__file__");
  if (file)
    Py_INCREF(file);
  else {
    file = BUILD_FILENAME(name);
    if (!file)
      return NULL;
  }

  DECODE_CODE_STRING(cipher_code);

  PyObject *ret = PyObject_CallFunction(f, PYARMOR_ARGUMENTS, name, file,
                                        cipher_code, sizeof(cipher_code), CIPHER_MODE);
  Py_DECREF(file);
  return ret;
}

#if (PY_MAJOR_VERSION >= 3)

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "XYZXYZ",
    NULL,
    -1,
    NULL
};

PyMODINIT_FUNC
PyInit_XYZXYZ(void)
{
  PyObject *f = import_pyarmor();
  if (!f)
    return NULL;

  PyObject *m = PyModule_Create(&module);
  if (!m)
    return NULL;

  PyObject *r = run_pyarmor(m, f);
  if (!r) {
    Py_DECREF(m);
    m = NULL;
  }
  Py_XDECREF(r);

  return m;
}

#else

PyMODINIT_FUNC
initXYZXYZ(void)
{
  PyObject *f = import_pyarmor();
  if (!f)
    return;

  PyObject *m = Py_InitModule("XYZXYZ", NULL);
  if (!m)
    return;

  PyObject *r = run_pyarmor(m, f);
  if (!r)
    Py_DECREF(m);
  Py_XDECREF(r);
}

#endif

'''


def re_encode_code_string(code):
    n = len(code)
    i = random.randrange(0, n)
    j = random.randrange(0, n)
    k = random.randrange(0, 256)
    code[i] -= 1
    code[j] ^= k
    return r'''
#define DECODE_CODE_STRING(code) do { \
        code[%s] ++;                  \
        code[%s] ^= %s;               \
    } while (0)
''' % (i, j, k)


def makedirs(path, exist_ok=False):
    if not (exist_ok and os.path.exists(path)):
        os.makedirs(path)


def make_cfile(filename, output=None):
    logger.info('Analysis "%s"', filename)

    name = os.path.basename(filename).rsplit('.', 1)[0]
    pytransform_name = 'pytransform'
    pyarmor_name = ''

    with open(filename) as f:
        for line in f:
            if line.startswith('from'):
                pytransform_name = line.strip().split()[1]
            elif line.find('__file__') > 0:
                pyarmor_name, parastr = line.strip().split('(', 1)
                paras = parastr.strip()[:-1].split(',')
                cipher_mode = paras[-1]
                cipher_code = list(bytearray(eval(paras[-2])))
                break

    if pyarmor_name.find('pyarmor') == -1:
        logger.warning('%s is not obfuscated script' % filename)
        return

    super_mode = pyarmor_name.startswith('pyarmor')

    logger.info('extension name is "%s"', name)
    logger.info('pyarmor name is "%s"', pyarmor_name)
    logger.info('pytransform name is "%s"', pytransform_name)
    logger.info('super mode is %s', super_mode)
    logger.info('cipher mode is %s', cipher_mode)

    decode_code_string_macro = re_encode_code_string(cipher_code)

    macros = [
        '/* Generated by PyArmor Helper 0.1 */',
        '#define PYARMOR_SUPER_MODE' if super_mode else '',
        '#define PYARMOR_NAME "%s"' % pyarmor_name,
        '#define PYTRANSFORM_NAME "%s"' % pytransform_name,
        '#define CIPHER_MODE %s' % cipher_mode,
        '#define CIPHER_CODE %s' % repr(cipher_code)[1:-1],
        decode_code_string_macro,
        ''
    ]

    if output is None:
        output = filename[:-3] + '.c'
    logger.info('Write "%s"', output)
    with open(output, 'w') as f:
        f.write('\n'.join(macros))
        f.write(c_template.replace('XYZXYZ', name))

    return name, output


def excepthook(type, exc, traceback):
    if hasattr(exc, 'args'):
        logging.error(exc.args[0], *exc.args[1:])
    else:
        logging.error('%s', exc)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='build obfuscated scripts to extensions',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    parser.add_argument('-d', '--debug',
                        default=False,
                        action='store_true',
                        dest='debug',
                        help='print debug log (default: %(default)s)')
    parser.add_argument('-c',
                        default=True,
                        action='store_false',
                        dest='build',
                        help='generate .c file only (default: False)')
    parser.add_argument('scripts',
                        metavar='PATH',
                        nargs='+',
                        help="obfuscated script or path")

    args = parser.parse_args(sys.argv[1:])
    if args.debug:
        logger.setLevel(logging.DEBUG)
    else:
        sys.excepthook = excepthook

    filelist = []
    for pat in args.scripts:
        if pat.endswith('.py'):
            filelist.append(pat)
        elif os.path.isdir(pat):
            filelist.extend(glob.glob(os.path.join(pat, '*.py')))
        else:
            logger.warning('Ignore %s', pat)

    cfiles = []
    random.seed()
    for script in filelist:
        cfiles.append(make_cfile(script))

    if args.build:
        cfiles = filter(None, cfiles)
        setup(name='builder',
              script_args=['build_ext'],
              ext_modules=[Extension(k, sources=[v]) for k, v in cfiles])


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    main()
