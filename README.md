# coveralls.mk

An [Erlang.mk](https://github.com/ninenines/erlang.mk) plugin that grab and send coverage reports to coveralls.io

## Usage

In order to include this plugin in your project you just need to add the following in your Makefile:

```bash
DEP_PLUGINS = coveralls.mk
TEST_DEPS = coveralls.mk
dep_coveralls.mk = git https://github.com/erlangbureau/coveralls.mk master

include erlang.mk
```
