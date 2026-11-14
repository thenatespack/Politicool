defmodule PolticoolWeb.IssueCategoriesTest do
  use ExUnit.Case, async: true

  alias PolticoolWeb.IssueCategories

  test "parse/1 keeps known ids in display order" do
    assert IssueCategories.parse("water,housing,bogus") == ["housing", "water"]
    assert IssueCategories.parse("") == []
    assert IssueCategories.parse(nil) == []
  end

  test "toggle/2 adds and removes known ids and ignores unknown ones" do
    assert IssueCategories.toggle(["water"], "housing") == ["housing", "water"]
    assert IssueCategories.toggle(["housing", "water"], "housing") == ["water"]
    assert IssueCategories.toggle(["water"], "bogus") == ["water"]
  end

  test "slugs_for/1 and for_issue/1 cover pledge-extraction and seed slugs" do
    assert "environment" in IssueCategories.slugs_for(["water"])
    assert "great-salt-lake" in IssueCategories.slugs_for(["water"])
    assert IssueCategories.for_issue("income-tax").id == "education"
    assert IssueCategories.for_issue("taxes").id == "education"
    assert IssueCategories.for_issue("immigration") == nil
  end

  test "to_params/1" do
    assert IssueCategories.to_params([]) == %{}
    assert IssueCategories.to_params(["housing", "water"]) == %{issues: "housing,water"}
  end
end
