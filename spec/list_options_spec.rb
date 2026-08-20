# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Pagr.build_list_query" do
  let(:templates) { Pagr::Filters::TEMPLATES }
  let(:documents) { Pagr::Filters::DOCUMENTS }

  it "omits unset options" do
    expect(Pagr.build_list_query(templates, take: 5)).to eq({ "take" => 5 })
    expect(Pagr.build_list_query(templates)).to eq({})
  end

  it "emits paging, sorting and search params under their wire names" do
    query = Pagr.build_list_query(
      templates,
      skip: 10, take: 5, sort_by: "name", sort_direction: "desc", search: "inv"
    )
    expect(query).to eq(
      "skip" => 10, "take" => 5, "sortBy" => "name",
      "sortDirection" => "desc", "search" => "inv"
    )
  end

  it "expands hash filters to the indexed wire form, defaulting op to eq" do
    query = Pagr.build_list_query(
      templates,
      filters: [
        { field: "name", op: :contains, value: "inv" },
        { field: "project.guid", value: "abc" },
      ]
    )
    expect(query).to eq(
      "filters[0].field" => "name",
      "filters[0].op" => "contains",
      "filters[0].value" => "inv",
      "filters[1].field" => "project.guid",
      "filters[1].op" => "eq",
      "filters[1].value" => "abc"
    )
  end

  it "accepts Pagr::Filter objects as well as hashes" do
    query = Pagr.build_list_query(
      documents,
      filters: [Pagr::Filter.new(field: "environment", op: Pagr::FilterOp::NEQ, value: "test")]
    )
    expect(query).to eq(
      "filters[0].field" => "environment",
      "filters[0].op" => "neq",
      "filters[0].value" => "test"
    )
  end

  it "rejects a filter field the endpoint does not accept" do
    # The server silently ignores an unknown field and returns the UNFILTERED result
    # set, so a typo has to fail here rather than quietly return everything.
    expect do
      Pagr.build_list_query(templates, filters: [{ field: "projectName", value: "Sales" }])
    end.to raise_error(ArgumentError, /unknown field "projectName".*project\.guid/m)
  end

  it "rejects an operator that is not valid for the field" do
    expect do
      Pagr.build_list_query(templates, filters: [{ field: "project.guid", op: :contains, value: "abc" }])
    end.to raise_error(ArgumentError, /operator :contains is not valid/)
  end

  it "validates against the calling endpoint's table, not one global vocabulary" do
    filters = [{ field: "documentName", op: :contains, value: "invoice" }]
    expect(Pagr.build_list_query(documents, filters: filters)).to include("filters[0].field" => "documentName")
    expect { Pagr.build_list_query(templates, filters: filters) }.to raise_error(ArgumentError)
  end
end
