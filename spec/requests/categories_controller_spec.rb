# frozen_string_literal: true

require 'rails_helper'

describe CategoriesController do
  let(:admin) { Fabricate(:admin) }
  let!(:category) { Fabricate(:category, user: admin) }

  context '#create' do
    it "requires the user to be logged in" do
      post "/categories.json"
      expect(response.status).to eq(403)
    end

    describe "logged in" do
      before do
        Jobs.run_immediately!
        sign_in(admin)
      end

      it "regular ICIJ users do have permission to create categories" do
        user = Fabricate(:user)
        sign_in(user)

        create_post = CategoryGroup.permission_types[:create_post]

        group = Fabricate(:icij_group)
        group.add(user)

        post "/categories.json", params: {
          name: 'hello',
          color: 'ff0',
          text_color: 'fff',
          permissions: {
            "#{group.name}" => :full
          }
        }

        expect(response.status).to eq(200)
      end

      describe "success" do
        it "works, if permissions are defined" do
          readonly = CategoryGroup.permission_types[:readonly]
          create_post = CategoryGroup.permission_types[:create_post]

          group = Fabricate(:icij_group)
          group.add(admin)

          post "/categories.json", params: {
            name: "hello",
            color: "ff0",
            text_color: "fff",
            slug: "hello-cat",
            auto_close_hours: 72,
            permissions: {
              "#{group.name}" => :full
            }
          }

          expect(response.status).to eq(200)
          category = Category.find_by(name: "hello")
          expect(category.category_groups.map { |g| [g.group_id, g.permission_type] }.sort).to eq([
            [group.id, 0]
          ])
          expect(category.name).to eq("hello")
          expect(category.slug).to eq("hello-cat")
          expect(category.color).to eq("ff0")
          expect(category.auto_close_hours).to eq(72)
          expect(UserHistory.count).to eq(4) # 1 + 3 (bootstrap mode)
        end
      end

      describe "failure" do
        it "does not work, if permissions are not defined" do
          readonly = CategoryGroup.permission_types[:readonly]
          create_post = CategoryGroup.permission_types[:create_post]

          group = Fabricate(:icij_group)

          post "/categories.json", params: {
            name: "hello",
            color: "ff0",
            text_color: "fff",
            slug: "hello-cat",
            auto_close_hours: 72,
            permissions: {}
          }

          expect(response.status).to eq(422)
          expect(response.body).to eq("{\"errors\":[\"Please assign a project to this group.\"]}")
        end

        it "does not work, if permissions are for a group to which the user is not a member" do
          another_user = Fabricate(:user)
          sign_in(another_user)

          readonly = CategoryGroup.permission_types[:readonly]
          create_post = CategoryGroup.permission_types[:create_post]

          group = Fabricate(:icij_group)
          group.add(another_user)
          another_group = Fabricate(:icij_group)

          post "/categories.json", params: {
            name: "hello",
            color: "ff0",
            text_color: "fff",
            slug: "hello-cat",
            auto_close_hours: 72,
            permissions: {
              "#{another_group.name}" => :full
            }
          }

          expect(response.status).to eq(422)
          expect(response.body).to eq("{\"errors\":[\"You are not a member of this project.\"]}")
        end
      end
    end
  end
end
