---
layout: page
permalink: /publications/
title: papers
# description: publications by categories in reversed chronological order. generated by jekyll-scholar.
years: [2023, 2022, 2020, 2019, 2018]
nav: true
---

<div class="publications">

{% for y in page.years %}
  <h2 class="year">{{y}}</h2>
  {% bibliography -f papers -q @*[year={{y}}]* %}
{% endfor %}

</div>
