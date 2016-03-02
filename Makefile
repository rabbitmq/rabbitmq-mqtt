PROJECT = rabbitmq_mqtt

DEPS = amqp_client

TEST_DEPS = rabbitmq_test rabbitmq_java_client emqttc

dep_emqttc = git https://github.com/emqtt/emqttc.git master

DEP_PLUGINS = rabbit_common/mk/rabbitmq-plugin.mk

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

# --------------------------------------------------------------------
# Testing.
# --------------------------------------------------------------------

WITH_BROKER_TEST_MAKEVARS := \
	RABBITMQ_CONFIG_FILE=$(TEST_TMPDIR)/etc/test
WITH_BROKER_TEST_ENVVARS := \
	SSL_CERTS_DIR=$(TEST_TMPDIR)/etc/certs
WITH_BROKER_TEST_SCRIPTS := $(CURDIR)/test/test.sh
WITH_BROKER_SETUP_SCRIPTS := $(CURDIR)/test/setup-rabbit-test.sh

WITH_BROKER_TEST_COMMANDS := eunit:test(rabbit_mqtt_reader)
STANDALONE_TEST_COMMANDS := eunit:test(rabbit_mqtt_util)

pre-standalone-tests:: test-tmpdir test-dist
	$(verbose) rm -rf $(TEST_TMPDIR)/etc
	$(exec_verbose) mkdir -p $(TEST_TMPDIR)/etc/certs
	$(verbose) sed -E -e "s|%%CERTS_DIR%%|$(TEST_TMPDIR)/etc/certs|g" \
		< test/src/test.config > $(TEST_TMPDIR)/etc/test.config
	$(verbose) $(MAKE) -C $(DEPS_DIR)/rabbitmq_test/certs all PASSWORD=bunnychow \
		DIR=$(TEST_TMPDIR)/etc/certs
	$(verbose) cp test/src/rabbitmq_mqtt_standalone.app.src test/rabbitmq_mqtt.app
