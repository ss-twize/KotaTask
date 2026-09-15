package com.mark.app.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.mark.app.databinding.ItemFolderBinding

/**
 * Универсальная "папка" в FoldersFragment.
 *  - id: null означает "Без категории" (системная папка, не удаляется)
 *  - count: число активных задач в этой папке
 */
data class FolderItem(
    val id: String?,
    val name: String,
    val count: Int
)

class FolderAdapter(
    private val onClick: (FolderItem) -> Unit,
    private val onDelete: ((FolderItem) -> Unit)? = null
) : ListAdapter<FolderItem, FolderAdapter.VH>(Diff) {

    object Diff : DiffUtil.ItemCallback<FolderItem>() {
        override fun areItemsTheSame(a: FolderItem, b: FolderItem) = a.id == b.id && a.name == b.name
        override fun areContentsTheSame(a: FolderItem, b: FolderItem) = a == b
    }

    inner class VH(val b: ItemFolderBinding) : RecyclerView.ViewHolder(b.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
        val b = ItemFolderBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return VH(b)
    }

    override fun onBindViewHolder(holder: VH, position: Int) {
        val item = getItem(position)
        holder.b.tvFolderName.text = item.name
        holder.b.tvFolderCount.text = item.count.toString()
        holder.b.folderCard.setOnClickListener { onClick(item) }

        val canDelete = item.id != null && onDelete != null
        holder.b.btnDeleteFolder.isVisible = canDelete
        if (canDelete) {
            holder.b.btnDeleteFolder.setOnClickListener { onDelete!!(item) }
        }
    }
}
