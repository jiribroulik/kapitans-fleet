local deployments = import "./deployments.jsonnet";
local pvcs = import "./pvcs.jsonnet";
local kube = import "lib/kube.libjsonnet";
local kap = import "lib/kapitan.libjsonnet";
local inv = kap.inventory();
local server = inv.parameters.gerrit.server;
local database = inv.parameters.gerrit.database;
local secret = inv.parameters.gerrit.secret;

{
  gerrit_secret: kube.Secret(secret.name) {
    data_: {
      "GERRIT_ADMIN_PWD": secret.data.admin_password,
      "GERRIT_DB_PASSWORD": secret.data.gerrit_db_password,
      "MYSQL_ROOT_PASSWORD": secret.data.mysql_root_password,
    }
  },

  local c = self,
  gerrit_deployment: deployments.GerritDeployment(server.deployment.name){
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            gerrit+: { env_+: { DB_ENV_MYSQL_PASSWORD: kube.SecretKeyRef($.gerrit_secret, "GERRIT_DB_PASSWORD"), LDAP_PASSWORD: kube.SecretKeyRef($.gerrit_secret, "GERRIT_ADMIN_PWD"),
                                GERRIT_ADMIN_PWD: kube.SecretKeyRef($.gerrit_secret, "GERRIT_ADMIN_PWD")} }
          },
        },
      },
    },
  },
  mysql_deployment: deployments.MysqlDeployment(database.deployment.name){
    spec+: {
      template+: {
        spec+: {
          containers_+: {
            mysql+: { env_+: { MYSQL_ROOT_PASSWORD: kube.SecretKeyRef($.gerrit_secret, "MYSQL_ROOT_PASSWORD"), MYSQL_PASSWORD: kube.SecretKeyRef($.gerrit_secret, "GERRIT_DB_PASSWORD")} }
          },
        },
      },
    },
  },

  gerrit_service: kube.Service(server.service.name) {
      type:: server.service.type,
      target_pod:: c["gerrit_deployment"].spec.template,
      target_container_name:: "gerrit",
      spec+:{
          clusterIP: if ("clusterip" in server.service) then server.service.clusterip else {},
      },
  },

  mysql_service: kube.Service(database.service.name) {
      type:: database.service.type,
      target_pod:: c["mysql_deployment"].spec.template,
      target_container_name:: "mysql",
      spec+:{
          clusterIP: if ("clusterip" in database.service) then database.service.clusterip else {},
      },
  },

  gerrit_pvc_reviewsite: if (server.deployment.volumes.reviewsite.type == "PersistentVolumeClaim") then pvcs.reviewsite else {},
  gerrit_pvc_database: if (database.deployment.volumes.database.type == "PersistentVolumeClaim") then pvcs.database else {},
}