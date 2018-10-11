import ComboBoxComponent from "select-kit/components/combo-box";
import { ajax } from 'discourse/lib/ajax';
import { on } from "ember-addons/ember-computed-decorators";
import computed from "ember-addons/ember-computed-decorators";
import PermissionType from "discourse/models/permission-type";
import Category from "discourse/models/category";
import { categoryBadgeHTML } from "discourse/helpers/category-link";
const { get, isNone, isEmpty } = Ember;

export default ComboBoxComponent.extend({
  pluginApiIdentifiers: ["category-chooser"],
  classNames: "project-category-chooser",
  filterable: true,
  castInteger: true,
  allowUncategorized: false,
  rowComponent: "category-row",
  noneRowComponent: "none-category-row",
  allowSubCategories: true,
  permissionType: PermissionType.FULL,

  init() {
    this._super();

    this.get("rowComponentOptions").setProperties({
      allowUncategorized: this.get("allowUncategorized"),
    });
  },

  filterComputedContent(computedContent, computedValue, filter) {
    if (isEmpty(filter)) { return computedContent; }

    const _matchFunction = (f, text) => {
      return text.toLowerCase().indexOf(f) > -1;
    };
    const lowerFilter = filter.toLowerCase();

    return computedContent.filter(c => {
      const category = Category.findById(get(c, "value"));
      const text = get(c, "name");
      if (category && category.get("parentCategory")) {
        const categoryName = category.get("parentCategory.name");
        return _matchFunction(lowerFilter, text) || _matchFunction(lowerFilter, categoryName);
      } else {
        return _matchFunction(lowerFilter, text);
      }
    });
  },

  @computed("rootNone", "rootNoneLabel")
  none(rootNone, rootNoneLabel) {
    if (this.siteSettings.allow_uncategorized_topics || this.get("allowUncategorized")) {
      if (!isNone(rootNone)) {
        return rootNoneLabel || "category.none";
      } else {
        return Category.findUncategorized();
      }
    } else {
      return "category.choose";
    }
  },

  computeHeaderContent() {
    let content = this._super();

    if (this.get("hasSelection")) {
      const category = Category.findById(content.value);
      const parentCategoryId = category.get("parent_category_id");
      const hasParentCategory = Ember.isPresent(parentCategoryId);

      let badge = "";

      if (hasParentCategory) {
        const parentCategory = Category.findById(parentCategoryId);
        badge += categoryBadgeHTML(parentCategory, {
          link: false,
          allowUncategorized: true
        }).htmlSafe();
      }

      badge += categoryBadgeHTML(category, {
        link: false,
        hideParent: hasParentCategory ? true : false,
        allowUncategorized: true
      }).htmlSafe();

      content.label = badge;
    }

    return content;
  },

  @on("didRender")
  _bindComposerResizing() {
    this.appEvents.on("composer:resized", this, this.applyDirection);
  },

  @on("willDestroyElement")
  _unbindComposerResizing() {
    this.appEvents.off("composer:resized");
  },

  didSelect(computedContentItem) {
    if (this.attrs.onChooseCategory) {
      this.attrs.onChooseCategory(computedContentItem.originalContent);
    }
  },

  computeContent() {
    let pathNames = document.location.pathname.split('/');
    let groupName = pathNames[2]

    if ((pathNames.length === 4) && (pathNames[3] === "categories")) {
      let categoriesSort = Discourse.SiteSettings.fixed_category_positions_on_create ?
        Category.list() :
        Category.listByActivity();

        let groupCategories = [];

        categoriesSort.forEach(function(c) {
          if (c.group_names.includes(groupName) || c.subcategory_group_names.includes(groupName)) {
            groupCategories.push(c);
          };
        });

        const categories = groupCategories

        return categories
    } else {
      const categories = Discourse.SiteSettings.fixed_category_positions_on_create ?
        Category.list() :
        Category.listByActivity();

        return categories
    }

    let scopedCategoryId = this.get("scopedCategoryId");
    if (scopedCategoryId) {
      const scopedCat = Category.findById(scopedCategoryId);
      scopedCategoryId = scopedCat.get("parent_category_id") || scopedCat.get("id");
    }

    const excludeCategoryId = this.get("excludeCategoryId");

    return categories.filter(c => {
      const categoryId = this.valueForContentItem(c);

      if (scopedCategoryId && categoryId !== scopedCategoryId && get(c, "parent_category_id") !== scopedCategoryId) {
        return false;
      }

      if (this.get("allowSubCategories") === false && c.get("parentCategory") ) {
        return false;
      }

      if ((this.get("allowUncategorized") === false && get(c, "isUncategorizedCategory")) || excludeCategoryId === categoryId) {
        return false;
      }

      if (this.get("permissionType")) {
        return this.get("permissionType") === get(c, "permission");
      }

      return true;
    });
  }
});
