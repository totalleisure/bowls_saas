/// Rows must be scoped to the current member and is_selected=true.
/// Once a published selection exists, its response replaces availability,
/// including after accepting or declining and for selected reserves.
Set<String> publishedSelectionFixtureIds(Iterable<Map<String, dynamic>> rows) {
  return {
    for (final row in rows)
      if (row['team_selections'] case final Map selection)
        if (selection['status'] == 'published')
          if (selection['fixture'] case final Map fixture)
            if (fixture['id'] case final String id) id,
  };
}
