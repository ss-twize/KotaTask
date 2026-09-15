package com.mark.app.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.mark.app.databinding.ItemCategoryRowBinding

/** Простая строка категории (id, name) с действиями rename/delete. */
data class CategoryRow(val id: String, val name: String)

class CategoryRowAdapter(
    private val onRename: (CategoryRow) -> Unit,
    private val onDelete: (CategoryRow) -> Unit
) : ListAdapter<CategoryRow, CategoryRowAdapter.VH>(Diff) {

    object Diff : DiffUtil.ItemCallback<CategoryRow>() {
        override fun areItemsTheSame(a: CategoryRow, b: CategoryRow) = a.id == b.id
        override fun areContentsTheSame(a: CategoryRow, b: CategoryRow) = a == b
    }

    inner class VH(val b: ItemCategoryRowBinding) : RecyclerView.ViewHolder(b.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val b = ItemCategoryRowBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(b)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val item = getItem(position)
        holder.b.tvCatName.text = item.name
        holder.b.btnRename.setOnClickListener { onRename(item) }
        holder.b.btnDelete.setOnClickListener { onDelete(item) }
    }
}
