import EditCategoryGeneral from 'discourse/components/edit-category-general'
import PermissionType from "discourse/models/permission-type";

export default {
  name: 'extend-edit-category-general-for-projects',
  initialize() {

    EditCategoryGeneral.reopen({

      editingPermissions: false,
      selectedGroup: null,
      selectedPermission: null,

      actions: {
        showCategoryTopic() {
          DiscourseURL.routeTo(this.get("category.topic_url"));
          return false;
        },

        editPermissions() {
          if (!this.get("category.is_special")) {
            this.set("editingPermissions", true);
          }
        },

        addPermission(group, id) {
          if (!this.get("category.is_special")) {
            this.get("category").addPermission({
              group_name: group + "",
              permission: PermissionType.create({ id: parseInt(id) })
            });
          }

          this.set(
            "selectedGroup",
            this.get("category.availableGroups.firstObject")
          );
        },

        removePermission(permission) {
          if (!this.get("category.is_special")) {
            this.get("category").removePermission(permission);
          }
        }
      }

    });
  }
};
