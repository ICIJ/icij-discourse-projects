import property from 'ember-addons/ember-computed-decorators';
import Group from 'discourse/models/group';
import Site from 'discourse/models/site';
import { ajax } from "discourse/lib/ajax";
import EmberObject from "@ember/object";
import User from "discourse/models/user";



export default {
  name: 'extend-group-model-for-projects',
  initialize() {

    Group.reopenClass({
      selectIcijProjects() {
        return User.currentProp("current_user_icij_projects");
      }
    });
  }
};
