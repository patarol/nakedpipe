#' @export
#' @rdname nakedpipe
`%D.%` <- function(x, expr){
  pf <- parent.frame()
  #dot_backup <- if (exists(".", pf)) get(".", pf) else substitute()

  expr <- substitute(expr)

  if (is.call(expr) && identical(expr[[1]], quote(`{`)))
    expr <- as.list(expr)[-1] else
      expr <- list(expr)

  body <- lapply(
    expr,
    function(expr) {
      if (has_assignment_op(expr)) {
        if (has_dbl_tilde(expr[[2]])) {
          expr[[2]] <- expr[[c(2,2,2)]]
          if(substr(as.character(expr[[2]]), 1, 1) == ".")
            return(expr)
          return(bquote(side_effect(.(expr))))
        }
        if (has_dbl_tilde(expr[[3]])) {
          expr[[3]] <- expr[[c(3,2,2)]]
          if(substr(as.character(expr[[2]]), 1, 1) == ".")
            return(expr)
          return(bquote(side_effect(.(expr))))
        }

        stop("Wrong syntax! If you mean to assign as a side effect you should",
             "use a `~~` prefix")
      }
      if (has_dbl_tilde(expr)) {
        expr <- expr[[c(2,2)]]
        return(bquote(side_effect(.(expr))))
      }
      if (has_equal(expr)) {
        expr <- as.call(c(quote(transform), setNames(list(expr[[3]]), as.character(expr[[2]]))))
      }
      if (has_logic_or_comparison(expr)) {
        expr <- call("subset", expr)
      }
      if (has_dt(expr)) {
        expr <- bquote({
          .dt <- data.table::as.data.table(.)
          .dt <- .(expr)
          data.table::setDF(.dt)
          class(.dt) <- class(.)
          . <- .dt
          })
        return(expr)
      }

      # nocov start
      if (has_tb(expr)) {
        expr <- bquote({
          .tb <- as_tb(.)
          .tb <- .(expr)
          class(.tb) <- class(.)
          . <- .tb
        })
        return(expr)
      }
      # nocov end

      if (has_if(expr)) {
        expr[[3]] <- insert_dot(expr[[3]])
        if (length(expr) == 4) {
          expr[[4]] <- insert_dot(expr[[4]])
        } else {
          expr[[4]] <- quote(.)
        }
        expr <- bquote(. <- .(expr))
        return(expr)
      }

      expr <- insert_dot(expr)
      as.call(c(quote(`<-`), quote(.), expr))
    })
  body <- c(
    as.call(c(quote(`<-`), quote(.), substitute(x))),
    body
  )

  nakedpipe_debugger <- as.function(alist(NULL))
  body(nakedpipe_debugger) <- as.call(c(quote(`{`),body))
  environment(nakedpipe_debugger) <- pf
  debugonce(nakedpipe_debugger)
  res <- nakedpipe_debugger()
  return(res)
}


#' Produce a side effect from the nakedpipe debugger
#'
#' This function should only be called inside `nakedpipe_debugger()`, which is
#' created and run when calling `%D.%`. You will
#' find it there to transcribe the side effects prefixed by `~~` in the pipe.
#'
#' `side_effect()` acts as if it evaluates its argument in the calling environment of the
#' pipe, but making the current value of the dot available. If an assignment is
#' used inside `side_effect()` a variable will be created or modified in the
#' calling environment of the pipe.
#'
#' @return the value of `.` in the calling environment before `side_effect()`
#' was called.
#'
#' @param expr expr
#' @export
side_effect <- function(expr){
  if (!identical(
    eval.parent(quote(match.call())),
    quote(nakedpipe_debugger())))
    stop("`side_effect()` should only be called inside `nakedpipe_debugger()`!") # nocov
  pf <- parent.frame(3)
  # evaluate
  env <- new.env()
  dot_val <- eval.parent(quote(.))
  env$. <- dot_val
  eval(substitute(expr), envir = env, enclos = pf)
  list2env(x = as.list(env), envir = pf)
  dot_val
}
