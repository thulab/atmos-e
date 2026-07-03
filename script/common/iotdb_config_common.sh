#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
    echo "iotdb_config_common.sh requires bash" >&2
    return 1 2>/dev/null || exit 1
fi
if shopt -oq posix; then
    echo "iotdb_config_common.sh requires non-posix bash" >&2
    return 1 2>/dev/null || exit 1
fi

set_iotdb_datanode_heap_memory() {
    local datanode_env="$1"
    local heap_size="${2:-20G}"

    sed -i "s/^#\\?ON_HEAP_MEMORY=.*$/ON_HEAP_MEMORY=\"${heap_size}\"/" "${datanode_env}"
}

append_iotdb_metric_properties() {
    local properties_file="$1"
    local cluster_name="${2:-${TEST_TYPE:-IoTDB}}"

    cat >> "${properties_file}" <<EOF
cluster_name=${cluster_name}
cn_enable_metric=true
cn_enable_performance_stat=true
cn_metric_reporter_list=PROMETHEUS
cn_metric_level=ALL
cn_metric_prometheus_reporter_port=9081
dn_enable_metric=true
dn_enable_performance_stat=true
dn_metric_reporter_list=PROMETHEUS
dn_metric_level=ALL
dn_metric_prometheus_reporter_port=9091
EOF
}

append_iotdb_compaction_disabled_properties() {
    local properties_file="$1"

    cat >> "${properties_file}" <<EOF
enable_seq_space_compaction=false
enable_unseq_space_compaction=false
enable_cross_space_compaction=false
EOF
}
