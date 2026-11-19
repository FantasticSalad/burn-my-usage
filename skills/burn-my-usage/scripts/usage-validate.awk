# Validate JSON syntax and the legacy Claude tap schema without external JSON tools.
# No values from unknown fields are used. Duplicate object keys are rejected.
{ text = text $0 "\n" }
function space() { while (substr(text, pos, 1) ~ /[ \t\r\n]/ && pos <= length(text)) pos++ }
function str(  c, e, h, out) {
  escaped=0
  if (substr(text, pos++, 1) != "\"") { bad=1; return "" }
  out=""
  while (pos <= length(text)) {
    c=substr(text,pos++,1)
    if (c == "\"") return out
    if (c == "\\") {
      escaped=1
      e=substr(text,pos++,1)
      if (e == "u") {
        h=substr(text,pos,4); if (h !~ /^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/) bad=1
        pos+=4; out=out "?"
      } else if (e ~ /^["\\\/bfnrt]$/) out=out "?"
      else bad=1
    } else { if (c ~ /[[:cntrl:]]/) bad=1; out=out c }
  }
  bad=1; return out
}
function value(p,  c,key,child,n,tail,token) {
  space(); c=substr(text,pos,1)
  if (c == "{") {
    types[p]="object"; pos++; space()
    if (substr(text,pos,1)=="}") { pos++; return }
    while (!bad) {
      space(); if (substr(text,pos,1)!="\"") { bad=1; return }
      key=str(); if (escaped || key ~ /\//) { bad=1; return }; child=p "/" key
      if (seen[child]++) { bad=1; return }
      space(); if (substr(text,pos++,1)!=":") { bad=1; return }
      value(child); space(); c=substr(text,pos++,1)
      if (c=="}") return
      if (c!=",") { bad=1; return }
    }
  } else if (c == "[") {
    types[p]="array"; pos++; space(); n=0
    if (substr(text,pos,1)=="]") { pos++; return }
    while (!bad) {
      value(p "/[" n++ "]"); space(); c=substr(text,pos++,1)
      if (c=="]") return
      if (c!=",") { bad=1; return }
    }
  } else if (c == "\"") { types[p]="string"; values[p]=str() }
  else {
    tail=substr(text,pos)
    if (match(tail,/^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/)) {
      token=substr(tail,1,RLENGTH); pos+=RLENGTH; types[p]="number"; values[p]=token
    } else if (substr(tail,1,4)=="true" || substr(tail,1,4)=="null") { pos+=4; types[p]="literal" }
    else if (substr(tail,1,5)=="false") { pos+=5; types[p]="literal" }
    else bad=1
  }
}
END {
  pos=1; value(""); space()
  if (bad || pos<=length(text) || types[""]!="object" || types["/rate_limits"]!="object" ||
      types["/captured_at"]!="number" || values["/captured_at"] !~ /^[0-9]+$/ || values["/captured_at"]+0 > 4102444800) exit 1
  if (("/provider" in types) && (types["/provider"]!="string" || values["/provider"]!="claude-code")) exit 1
  split("seven_day five_hour spend_limit", windows, " ")
  for (i=1;i<=3;i++) {
    p="/rate_limits/" windows[i]
    if (p in types) {
      if (types[p]!="object" || types[p "/used_percentage"]!="number" ||
          values[p "/used_percentage"] !~ /^[0-9]+(\.[0-9]+)?$/ ||
          values[p "/used_percentage"]+0 > 100) exit 1
      if ((p "/resets_at") in types && (types[p "/resets_at"]!="number" || values[p "/resets_at"] !~ /^[0-9]+$/ || values[p "/resets_at"]+0 > 4102444800)) exit 1
      if (windows[i]=="seven_day" && types[p "/resets_at"]!="number") exit 1
    }
  }
  printf "{\"captured_at\":%s,\"rate_limits\":{", values["/captured_at"]
  sep=""
  for (i=1;i<=3;i++) {
    p="/rate_limits/" windows[i]
    if (p in types) {
      printf "%s\"%s\":{\"used_percentage\":%s", sep, windows[i], values[p "/used_percentage"]
      if ((p "/resets_at") in types) printf ",\"resets_at\":%s", values[p "/resets_at"]
      printf "}"; sep=","
    }
  }
  print "}}"
}
